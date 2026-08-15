#!/usr/bin/env python3
"""
bundle.py — combine the coreui/ ModuleScript tree into a single loadstring-able
Lua file.

Roblox's require(script.Parent.X) needs a real instance tree. loadstring() only
runs one source chunk, so we flatten every module into one file and emulate
require() with an in-file module registry.

A second, much smaller artifact is produced alongside it: `ui/screen.lua`, the
standalone status page (see build_screen below).

Usage:  python3 bundle.py  ->  writes coreui.bundle.lua + ui/
"""
import os, re, sys, shutil, subprocess
from datetime import datetime

BASE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(BASE, "coreui")
OUT  = os.path.join(BASE, "coreui.bundle.lua")

# The build-output folder the delivery worker copies from. `uibundle.lua` is a
# byte-for-byte mirror of coreui.bundle.lua — the canonical path stays
# coreui.bundle.lua because every shipped loadstring URL is pinned to it.
UI_DIR = os.path.join(BASE, "ui")
UI_BUNDLE = os.path.join(UI_DIR, "uibundle.lua")
UI_SCREEN = os.path.join(UI_DIR, "screen.lua")

# Source of the status page: one body, two preludes (see build_screen).
SCREEN_SRC = os.path.join(ROOT, "components", "Screen.lua")
SCREEN_PRELUDE = os.path.join(BASE, "standalone", "screen.prelude.lua")

# ui/screen.lua is inlined into *every* refusal reply the delivery worker sends,
# so its size is a per-request cost rather than a per-session one.
SCREEN_TARGET = 15 * 1024
SCREEN_CEILING = 30 * 1024


def build_version():
    """A human-readable build stamp printed on load so you can tell at a glance
    that the executor is running *this* build and not a stale CDN copy.

    Format: 'YYYY-MM-DD HH:MM:SS <shortsha>[-dirty]'. The timestamp is the real
    'is this current?' signal — it's fresh every build. The git short SHA is
    best-effort traceability; note push.py bundles *before* committing, so the
    SHA reflects the parent commit (the dirty flag shows the tree has the new
    changes not yet committed)."""
    stamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    try:
        sha = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            capture_output=True, text=True, cwd=os.path.dirname(OUT),
        ).stdout.strip()
        dirty = subprocess.run(
            ["git", "status", "--porcelain"],
            capture_output=True, text=True, cwd=os.path.dirname(OUT),
        ).stdout.strip()
        if sha:
            return f"{stamp} {sha}{'-dirty' if dirty else ''}"
    except Exception:
        pass
    return stamp

# require(script.a.b)  ->  capture the dotted chain
REQ = re.compile(r"require\(\s*(script(?:\.\w+)*)\s*\)")


def module_key(rel_path):
    """coreui/components/Window.lua -> 'components.Window'; init.lua -> '' (root)."""
    rel = rel_path[:-4]  # strip .lua
    if rel == "init":
        return ""
    return rel.replace(os.sep, ".")


def resolve(chain, own_key):
    """Resolve a `script.Parent.X...` chain relative to the module's own key."""
    parts = own_key.split(".") if own_key else []
    for seg in chain.split(".")[1:]:  # skip leading 'script'
        if seg == "Parent":
            if not parts:
                raise ValueError(f"{own_key}: '{chain}' walks above root")
            parts.pop()
        else:
            parts.append(seg)
    return ".".join(parts)


# ── Icon set ─────────────────────────────────────────────────────────────────
# LucideData ships ~1500 icons × two sprite sets. We always drop the "256px" set
# (nothing renders at that size — the UI runs 14–34px) and ship the **whole**
# "48px" set by default.
#
# Why not tree-shake: `Icon` fields are consumer-facing. Downstream menus pass
# arbitrary Lucide names ("globe", "zap", "gamepad-2"), and a name with no entry
# falls through to the "•" glyph in Icons.lua — no error, the icon just silently
# disappears. Shipping every name costs bundle *bytes* and nothing else: entries
# are {assetId,{w,h},{offX,offY}} text, and only the spritesheets an icon
# actually references get fetched at runtime.
#
# `--shake` opts back into the old minimal build (ALIAS values + literal names
# passed to Icons.new/apply); EXTRA_ICONS lists raw names to force-keep there.
#
# The status page (components/Screen.lua) picks its icon from a caller-supplied
# `Icon` option, so no literal reaches collect_used_icons — these are the names
# the two known callers pass. They also seed the standalone build's inlined
# icon table (build_screen).
SCREEN_ICONS = {
    "triangle-alert", "octagon-alert", "ban", "wrench", "download",
    "pause", "package", "refresh-cw", "message-circle",
    # The key gate: its page icon, and the icons on its two Actions. `clipboard`
    # is also a body literal (the Input block's paste affordance), but the gate
    # passes it too and the set dedupes.
    "key", "external-link", "clipboard",
}

EXTRA_ICONS: set = set(SCREEN_ICONS)

# name={...} or ["name"]={...} where the value is {id,{w,h},{offX,offY}}
ICON_ENTRY = re.compile(
    r'(\["[^"]+"\]|[A-Za-z_]\w*)=(\{\d+,\{\d+,\d+\},\{\d+,\d+\}\})'
)


def _entry_name(raw_key):
    """'["mouse-pointer"]' -> 'mouse-pointer'; 'home' -> 'home'."""
    if raw_key.startswith('["'):
        return raw_key[2:-2]
    return raw_key


def _extract_set(src, key):
    """Return the inner text of the `["key"]={ ... }` table, braces excluded."""
    start = src.find(f'["{key}"]=')
    if start == -1:
        return None
    brace = src.find("{", start)
    depth = 0
    for i in range(brace, len(src)):
        c = src[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return src[brace + 1 : i]
    return None


def collect_used_icons(mods):
    """Lucide names coreui can actually render: ALIAS values + literal names
    passed to Icons.new/Icons.apply (translated through ALIAS) + EXTRA_ICONS."""
    icons = mods.get("Icons", "")
    a, g = icons.find("local ALIAS"), icons.find("local GLYPH")
    alias_block = icons[a:g] if (a != -1 and g != -1) else icons
    alias = dict(re.findall(r'(\w+)\s*=\s*"([^"]+)"', alias_block))

    used = set(alias.values()) | set(EXTRA_ICONS)
    for src in mods.values():
        for name in re.findall(r'Icons\.new\(\s*"([^"]+)"', src):
            used.add(alias.get(name, name))
        for name in re.findall(r'Icons\.apply\([^,]+,\s*"([^"]+)"', src):
            used.add(alias.get(name, name))
    return used


def build_lucide(src, used=None):
    """Rewrite the LucideData module to a single "48px" set — every entry by
    default, or only `used` when tree-shaking. Returns (new_src, kept, total)."""
    inner = _extract_set(src, "48px")
    if inner is None:
        print("warn: could not find LucideData 48px set; leaving it untouched")
        return src, 0, 0

    entries = ICON_ENTRY.findall(inner)
    if used is None:
        kept, note = entries, "full Lucide 48px set"
    else:
        kept = sorted((raw, val) for raw, val in entries if _entry_name(raw) in used)
        note = "tree-shaken from the full Lucide set"
        missing = used - {_entry_name(raw) for raw, _ in entries}
        if missing:
            print(f"note: {len(missing)} name(s) have no 48px entry (glyph "
                  "fallback): " + ", ".join(sorted(missing)))

    body = ",".join(f"{raw}={val}" for raw, val in kept)
    new_src = (
        f"-- @generated by bundle.py ({note}); 256px set dropped.\n"
        "--!nocheck\n\n"
        f"return {{[\"48px\"]={{{body}}}}}\n"
    )
    return new_src, len(kept), len(entries)


def _kb(n):
    return f"{n:,} B ({n / 1024:.1f} KB)"


def _delta(n):
    sign = "+" if n >= 0 else "-"
    return f"{sign}{abs(n):,} B / {sign}{abs(n) / 1024:.1f} KB"


# ── the standalone status page ───────────────────────────────────────────────
# `ui/screen.lua` is the same failure page as `Uranium:Screen`, with none of the
# library behind it: the delivery worker inlines it into a refusal reply and
# evaluates it as `(function(...) <file> end)()`, on a client that has just been
# told no — so it can't require anything, can't fetch anything, and can't assume
# a hub exists.
#
# It is NOT a fork. There is one implementation of the page: the shared body of
# coreui/components/Screen.lua (everything after its `--@body` marker). Only the
# prelude differs — the library's requires the rest of the library,
# standalone/screen.prelude.lua inlines the handful of helpers it needs — and
# `--@lib`/`--@endlib` blocks (today: the `Detail` panel) are dropped here,
# because the refusal path never passes one and every byte is per-request.
#
# The palette, the icon slices and the ScreenGui identity attribute are INJECTED
# from Theme.lua / LucideData.lua / util/Gui.lua at build time rather than
# retyped, so the standalone can't drift out of the library's palette or stop
# being recognised by the singleton sweep.

BODY_MARK = "--@body"
LIB_OPEN, LIB_CLOSE = "--@lib", "--@endlib"
INJECT = re.compile(r"--@inject\s+(\w+)\s*$")


def _read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def strip_lib_regions(src):
    """Drop every `--@lib` … `--@endlib` block (library-only code)."""
    out, skip = [], False
    for line in src.splitlines():
        mark = line.strip()
        if mark == LIB_OPEN:
            if skip:
                sys.exit("error: nested --@lib region in Screen.lua")
            skip = True
            continue
        if mark == LIB_CLOSE:
            if not skip:
                sys.exit("error: stray --@endlib in Screen.lua")
            skip = False
            continue
        if not skip:
            out.append(line)
    if skip:
        sys.exit("error: unclosed --@lib region in Screen.lua")
    return "\n".join(out)


def compact(src):
    """Drop whole-line comments, blank lines and indentation.

    Deliberately NOT a minifier. It never touches a trailing comment (telling one
    from a `--` inside a string needs a real lexer) and never renames or rewrites
    anything — this is the file that has to work when everything else already
    failed, so nothing here is allowed to be clever. Indentation is free to go:
    Lua ignores leading whitespace, and the guard below rules out the one case
    where a line's leading text is data rather than code."""
    if "[[" in src:
        sys.exit("error: long strings/comments in the Screen source defeat the "
                 "line-based stripper — remove them or teach it to lex")
    out = []
    for line in src.splitlines():
        mark = line.strip()
        if not mark or mark.startswith("--"):
            continue
        out.append(mark)
    return "\n".join(out)


def screen_icons(names):
    """`name={id,{w,h},{x,y}}` pairs for `names`, straight out of LucideData."""
    inner = _extract_set(_read(os.path.join(ROOT, "LucideData.lua")), "48px")
    if inner is None:
        sys.exit("error: LucideData has no 48px set to build ui/screen.lua from")
    have = {_entry_name(raw): val for raw, val in ICON_ENTRY.findall(inner)}
    missing = sorted(n for n in names if n not in have)
    if missing:
        print("warn: no 48px entry for " + ", ".join(missing) +
              " — the standalone page will draw them as the fallback glyph")
    return ",".join(f'["{n}"]={have[n]}' for n in sorted(names) if n in have)


def screen_colors(used):
    """Theme.Colors as a literal, narrowed to the tokens the page reads.

    `used` is scraped out of the body rather than listed here — a hand-kept
    subset is exactly the sort of thing that goes stale the first time someone
    reaches for one more colour, and the failure would be a nil index inside the
    page that only shows up when the page does."""
    src = _read(os.path.join(ROOT, "Theme.lua"))
    found = re.findall(r'(\w+)\s*=\s*Color3\.fromHex\("([0-9A-Fa-f]{6})"\)', src)
    if not found:
        sys.exit("error: couldn't read Theme.Colors for the standalone page")
    have = dict(found)
    missing = sorted(n for n in used if n not in have)
    if missing:
        sys.exit("error: the status page reads Theme.Colors." +
                 ", Theme.Colors.".join(missing) + ", which Theme.lua doesn't define")
    return ",".join(f'{name}=Color3.fromHex("{have[name]}")' for name in sorted(used))


def screen_brand():
    """Theme.Brand.name, for the standalone page's wordmark — same reason the
    palette is injected rather than retyped: this build has to keep saying what
    the library says it's called."""
    src = _read(os.path.join(ROOT, "Theme.lua"))
    m = re.search(r'Theme\.Brand\s*=\s*\{[^}]*?\bname\s*=\s*"([^"]+)"', src, re.S)
    if not m:
        sys.exit("error: couldn't read Theme.Brand.name for the standalone page")
    return m.group(1)


def screen_mark():
    """Where util/Asset.lua caches the brand PNG on disk, plus Brand.zoom.

    The standalone page has no network, so the only real art it can reach is the
    copy the library downloaded during an earlier, working session —
    `getcustomasset` on that path needs nothing but the file. The path is
    `Asset.CacheFolder` + a djb2 hash of the URL, so it's derived here from the
    same three sources rather than pasted: a pasted one would go stale silently
    the first time any of them moved.

    Every failure here is soft — no logo URL, an unreadable Asset.lua, a hashing
    scheme that has since changed — because the page degrades to the accent
    square + initial it drew before this existed. It must never fail the build.
    """
    try:
        theme = _read(os.path.join(ROOT, "Theme.lua"))
        base = re.search(r'local ASSETS\s*=\s*"([^"]+)"', theme)
        logo = re.search(r"logo\s*=\s*\{\s*(?:ASSETS\s*\.\.\s*)?\"([^\"]+)\"", theme)
        zoom = re.search(r"\bzoom\s*=\s*([0-9.]+)", theme)
        folder = re.search(r'Asset\.CacheFolder\s*=\s*"([^"]+)"',
                           _read(os.path.join(ROOT, "util", "Asset.lua")))
        if not (base and logo and folder):
            raise ValueError("no cacheable brand logo")
        url = logo.group(1)
        if not url.startswith("http"):
            url = base.group(1) + url
        ext = url.rsplit(".", 1)[-1].lower()
        if ext not in ("png", "jpg", "jpeg", "webp", "tga", "bmp"):
            ext = "png"
        h = 5381
        for byte in url.encode("utf-8"):
            h = (h * 33 + byte) % 4294967296
        path = f"{folder.group(1)}/{h:010d}.{ext}"
        return path, float(zoom.group(1)) if zoom else 1.0
    except Exception as err:  # noqa: BLE001 — soft by design, see the docstring
        print(f"warn: no cached brand mark for the standalone page ({err}) — "
              "it will draw the fallback square")
        return "", 1.0


def screen_attribute():
    """util/Gui.lua's identity attribute, so the singleton sweep in a later
    library load finds and clears a stale standalone page."""
    src = _read(os.path.join(ROOT, "util", "Gui.lua"))
    m = re.search(r'Gui\.Attribute\s*=\s*"([^"]+)"', src)
    if not m:
        sys.exit("error: couldn't read Gui.Attribute for the standalone page")
    return m.group(1)


def build_screen(version):
    src = _read(SCREEN_SRC)
    at = src.find("\n" + BODY_MARK)
    if at == -1:
        sys.exit(f"error: {BODY_MARK} marker missing from coreui/components/Screen.lua")
    body = compact(strip_lib_regions(src[at + len(BODY_MARK) + 1:]))

    # Names the body still asks for by literal, plus the ones callers pass.
    icons = set(SCREEN_ICONS)
    icons |= set(re.findall(r'newIcon\(\s*"([^"]+)"', body))
    icons |= set(re.findall(r'putIcon\([^,]+,\s*"([^"]+)"', body))
    colors = set(re.findall(r"\bC\.(\w+)", body))

    mark_path, mark_zoom = screen_mark()
    values = {
        "MARK": f'local MARK, ZOOM = "{mark_path}", {mark_zoom:g}',
        "COLORS": "local C = {" + screen_colors(colors) + "}",
        "ICONS": "local ICONS = {" + screen_icons(icons) + "}",
        "ATTR": f'local ATTR = "{screen_attribute()}"',
        "BRAND": f'local BRAND = "{screen_brand()}"',
    }
    seen = set()
    lines = []
    for line in _read(SCREEN_PRELUDE).splitlines():
        m = INJECT.search(line)
        if m:
            key = m.group(1)
            if key not in values:
                sys.exit(f"error: unknown --@inject {key} in screen.prelude.lua")
            seen.add(key)
            lines.append(values[key])
        else:
            lines.append(line)
    unused = sorted(set(values) - seen)
    if unused:
        sys.exit("error: screen.prelude.lua is missing --@inject " + ", ".join(unused))
    prelude = compact("\n".join(lines))

    out = (
        "-- Uranium status page (standalone) — generated by bundle.py from\n"
        "-- coreui/components/Screen.lua + standalone/screen.prelude.lua.\n"
        "-- Do not edit by hand; edit those two and rebuild.\n"
        f"-- build: {version}\n"
        "-- The chunk's value is the function: show(opts) -> handle.\n"
        f"{prelude}\n{body}\n"
    )
    os.makedirs(UI_DIR, exist_ok=True)
    # LF explicitly: this file is inlined into a reply verbatim, and text mode on
    # Windows would quietly add ~1 byte per line (≈4% here) to every one of them.
    with open(UI_SCREEN, "w", encoding="utf-8", newline="\n") as f:
        f.write(out)

    size = os.path.getsize(UI_SCREEN)
    note = ""
    if size > SCREEN_CEILING:
        note = f"  ** OVER the {SCREEN_CEILING // 1024} KB ceiling **"
    elif size > SCREEN_TARGET:
        note = f"  (over the {SCREEN_TARGET // 1024} KB target, under the ceiling)"
    print(f"wrote {UI_SCREEN}  ({_kb(size)}, {len(icons)} icons inlined){note}")
    return size


def collect():
    mods = {}
    for dirpath, _, files in os.walk(ROOT):
        for f in files:
            if not f.endswith(".lua"):
                continue
            full = os.path.join(dirpath, f)
            rel = os.path.relpath(full, ROOT)
            mods[module_key(rel)] = open(full, encoding="utf-8").read()
    if "" not in mods:
        sys.exit("error: coreui/init.lua not found")
    return mods


def main():
    shake = "--shake" in sys.argv
    mods = collect()

    if "LucideData" in mods:
        used = collect_used_icons(mods) if shake else None
        mods["LucideData"], kept, total = build_lucide(mods["LucideData"], used)
        if total:
            how = "tree-shaken" if shake else "full set"
            print(f"icons: {kept}/{total} 48px entries ({how}); dropped 256px set")

    version = build_version()
    # The chunk's varargs are threaded into every module, so util/Services.lua can
    # read `...` (a host cache passed as `loadstring(src)(Services)`) even though
    # it's wrapped in a function here. `...` is only legal inside a vararg
    # function, hence `function(...)` on every module.
    #
    # Nothing is printed unconditionally: the banner goes through util/Log.lua,
    # which is silent unless `getgenv().URANIUM_VERBOSE` was set before this ran
    # (CreateWindow{ Verbose = true } catches it later — Log.banner fires once).
    out = [
        "-- Uranium (bundled for loadstring) — generated by bundle.py, do not edit by hand.",
        f'-- build: {version}',
        "local __chunk = table.pack(...)",
        "local __modules, __cache = {}, {}",
        "local function __require(k)",
        "    local c = __cache[k]; if c then return c[1] end",
        "    local f = __modules[k]; if not f then error('Uranium: missing module '..k, 2) end",
        "    local v = f(table.unpack(__chunk, 1, __chunk.n)); __cache[k] = { v }; return v",
        "end",
        "",
    ]
    for key, src in sorted(mods.items()):
        # rewrite every require(script...) to __require("resolved.key")
        def sub(m):
            return f'__require("{resolve(m.group(1), key)}")'
        src = REQ.sub(sub, src)
        out.append(f'__modules[{key!r}] = function(...)')
        out.append(src)
        out.append("end")
        out.append("")
    # root = init.lua, returns the library table
    out += [
        'local __lib = __require("")',
        'pcall(function()',
        '    local __log = __require("util.Log")',
        f'    __log.Build = "{version}"',
        f'    __lib.Build = "{version}"',
        '    __log.banner()',
        'end)',
        'return __lib',
    ]

    before = os.path.getsize(OUT) if os.path.exists(OUT) else 0
    open(OUT, "w", encoding="utf-8").write("\n".join(out))
    after = os.path.getsize(OUT)
    print(f"wrote {OUT}  ({len(mods)} modules, build {version})")
    print(f"size: {_kb(before)} -> {_kb(after)}  ({_delta(after - before)})")

    # Build outputs, mirrored where the delivery worker picks them up.
    build_screen(version)
    shutil.copyfile(OUT, UI_BUNDLE)
    print(f"wrote {UI_BUNDLE}  (mirror of coreui.bundle.lua)")


if __name__ == "__main__":
    main()
