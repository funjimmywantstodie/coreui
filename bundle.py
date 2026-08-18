#!/usr/bin/env python3
"""
bundle.py — combine the coreui/ ModuleScript tree into a single loadstring-able
Lua file.

Roblox's require(script.Parent.X) needs a real instance tree. loadstring() only
runs one source chunk, so we flatten every module into one file and emulate
require() with an in-file module registry.

A second, much smaller artifact is produced alongside it: `ui/screen.lua`, the
standalone status page (see build_screen below). `ui/` also carries a mirror of
the bundle and of DOCS.md, which is the folder the Uranium repo copies in whole.

Every build is VERIFIED before it is written anywhere anyone can reach it — see
`verify` below. Nothing here used to parse its own output, so a syntax error in
any of the 41 modules sailed through `push.py` into a public commit and was
discovered in an executor console.

Usage:  python3 bundle.py  ->  writes coreui.bundle.lua + ui/
        python3 bundle.py --no-verify  ->  skip the toolchain checks
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
# ...and the consumer docs alongside them: the Uranium repo copies ui/ in as
# build artifacts, so a DOCS.md that only exists at the root of this repo is one
# hand-copy away from being a version behind the bundle it documents.
UI_DOCS = os.path.join(UI_DIR, "DOCS.md")

# Source of the status page: one body, two preludes (see build_screen).
SCREEN_SRC = os.path.join(ROOT, "components", "Screen.lua")
SCREEN_PRELUDE = os.path.join(BASE, "standalone", "screen.prelude.lua")

# ui/screen.lua is inlined into *every* refusal reply the delivery worker sends,
# so its size is a per-request cost rather than a per-session one.
#
# These are a REPORTING aid, not a budget the page has to be squeezed into. The
# numbers started at 15 KB / 30 KB, back when the page was a bare card and the
# worry was that a per-request cost would creep. It has since grown a titlebar,
# the brand mark, the fetch behind it and the key-gate input block, and every one
# of those was worth its bytes — so the limits have been raised to match rather
# than the page trimmed to fit them.
#
# Keep the print, because a page that doubles overnight is still worth noticing:
# a refusal reply goes out on a hot path. But it is a rare reply (a banned or
# stale client, not every session), and the client this page *lets through* is
# about to download a ~600 KB bundle — so don't refuse a genuine improvement here
# over a kilobyte.
SCREEN_TARGET = 32 * 1024
SCREEN_CEILING = 64 * 1024


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


# ── verification ─────────────────────────────────────────────────────────────
# Two checks, both run on every build, both cheap (<1s together).
#
# 1. **Does it parse?** Every module is concatenated into one chunk, so a single
#    `luau-compile` call validates all of them at once. Without this a syntax
#    error anywhere in coreui/ reached a public commit (push.py bundles, commits
#    and pushes in one go) and was found in an executor console.
#
# 2. **Does the standalone page only use names its prelude provides?** This is
#    the contract written out at the `--@body` marker in Screen.lua: the shared
#    body is copied verbatim into two builds, so it may only use the handful of
#    names BOTH preludes agree on. Lua does not error on an undefined global —
#    a body edit reaching for a library-only name compiles clean, ships, and
#    surfaces as a nil index *on the refusal page*, which is the one moment when
#    nothing else works either. `luau-analyze` reports exactly this as an unknown
#    global; everything legitimately unknown is listed below, so anything else is
#    a build failure.
#
# The checks are skipped (with a warning, never silently) when the Luau toolchain
# isn't installed — `rokit add luau-lang/luau` puts both binaries on PATH.

# Roblox datatypes/globals the engine provides. luau-analyze has no Roblox
# definitions loaded, so it reports all of these; they're fine everywhere.
ROBLOX_GLOBALS = {
    "Color3", "Enum", "Font", "Instance", "Random", "TweenInfo",
    "UDim", "UDim2", "Vector2", "Vector3", "game", "task", "warn",
}

# Executor globals. Every one of these is feature-detected at its use site (see
# util/Config.lua, util/Asset.lua, util/Gui.lua and the standalone prelude) —
# they're *expected* to be absent, which is why they're read defensively rather
# than declared. Adding one here is a deliberate act; that's the point.
EXEC_GLOBALS = {
    "cloneref", "gethui", "protect_gui", "syn", "getgenv",
    "getclipboard", "getclipboardtext", "setclipboard", "toclipboard",
    "getcustomasset", "getsynasset", "writefile", "readfile", "isfile",
    "makefolder", "isfolder", "delfile", "listfiles", "identifyexecutor",
}

ALLOWED_GLOBALS = ROBLOX_GLOBALS | EXEC_GLOBALS

UNKNOWN_GLOBAL = re.compile(r"Unknown global '([^']+)'")


def _tool(name):
    """Absolute path to a Luau tool, or None when it isn't installed."""
    return shutil.which(name)


def check_parses(path):
    """Fail the build unless `path` is syntactically valid Luau."""
    tool = _tool("luau-compile")
    if not tool:
        print(f"warn: luau-compile not on PATH — {os.path.basename(path)} NOT parse-checked")
        return False
    # Bytes, not text: `--binary` writes compiled bytecode to stdout on success,
    # which is not decodable and blew up the reader thread when it was captured
    # as text. Only the diagnostics on failure are ever read as characters.
    r = subprocess.run([tool, "--binary", path], capture_output=True)
    if r.returncode != 0:
        why = (r.stdout + r.stderr).decode("utf-8", "replace").strip()
        sys.exit(f"error: {path} does not parse\n{why}")
    print(f"ok: {os.path.basename(path)} parses")
    return True


def check_globals(path, extra=()):
    """Fail the build on any global `path` reads that nothing provides.

    luau-analyze exits non-zero on this codebase regardless (it has no Roblox
    type definitions loaded, so every `Instance`/`Color3` annotation is an
    'Unknown type'), so the exit code is ignored and only the unknown-GLOBAL
    diagnostics are read."""
    tool = _tool("luau-analyze")
    if not tool:
        print(f"warn: luau-analyze not on PATH — {os.path.basename(path)} NOT global-checked")
        return False
    # luau-analyze exits 0 and prints NOTHING for a file it can't open, so a bad
    # path reads exactly like a clean bill of health. The whole point of these
    # checks is that nothing passes silently, so the path is proved first.
    if not os.path.isfile(path):
        sys.exit(f"error: {path} does not exist — nothing was checked")
    r = subprocess.run([tool, path], capture_output=True)
    out = (r.stdout + r.stderr).decode("utf-8", "replace")
    if not out.strip():
        # Possible for a genuinely clean file, but on this codebase every module
        # trips 'Unknown type Instance' (no Roblox definitions are loaded), so
        # silence means the analyzer didn't actually read it.
        print(f"warn: luau-analyze produced no output for {os.path.basename(path)}"
              " — treating it as UNCHECKED")
        return False
    seen = set(UNKNOWN_GLOBAL.findall(out))
    stray = sorted(seen - ALLOWED_GLOBALS - set(extra))
    if stray:
        sys.exit(
            f"error: {path} reads {len(stray)} global(s) nothing provides: "
            + ", ".join(stray)
            + "\n       For ui/screen.lua this almost always means the shared body "
              "(coreui/components/Screen.lua, after --@body) used a name only the\n"
              "       library prelude defines — add it to standalone/screen.prelude.lua "
              "too, or move the code into a --@lib block.\n"
              "       If the name really is an engine/executor global, add it to "
              "ROBLOX_GLOBALS / EXEC_GLOBALS in bundle.py."
        )
    print(f"ok: {os.path.basename(path)} reads no unprovided globals")
    return True


def verify(paths):
    """Parse-check + global-check every build output. Returns False if the
    toolchain was missing, so the caller can say so loudly at the end."""
    complete = True
    for path in paths:
        complete &= check_parses(path)
        complete &= check_globals(path)
    return complete


# ── the load smoke test ──────────────────────────────────────────────────────
# Parsing proves the syntax; this proves the thing RUNS. Every module body
# executes, every require resolves in a workable order, every load-time constant
# is built, and the library table comes back with its API on it — the class of
# breakage whose only previous detector was pasting a loadstring into an executor
# and watching nothing happen.
#
# It is composed into ONE chunk rather than run as three modules, because the
# luau CLI gives every `require`d module its own environment: a Roblox stub in
# another file would set Color3/Enum/game for nobody. The bundle is spliced in
# the way a real consumer evaluates it — `(function(...) … end)()` — so the
# vararg plumbing util/Services.lua depends on is exercised too.

TESTS_DIR = os.path.join(BASE, "tests")
SMOKE_BUILD = os.path.join(TESTS_DIR, ".smoke.build.luau")


def smoke():
    stub = os.path.join(TESTS_DIR, "roblox.luau")
    checks = os.path.join(TESTS_DIR, "smoke.luau")
    if not (os.path.isfile(stub) and os.path.isfile(checks)):
        print("warn: tests/ is missing — the bundle was NOT load-tested")
        return False
    tool = _tool("luau")
    if not tool:
        print("warn: luau not on PATH — the bundle was NOT load-tested")
        return False

    chunk = "\n".join([
        "--!nocheck",
        "-- GENERATED by bundle.py from tests/roblox.luau + the bundle +",
        "-- tests/smoke.luau. Do not edit; it is rewritten on every build.",
        _read(stub),
        # pcall'd so a load failure reaches tests/smoke.luau as a message rather
        # than a raw traceback through the middle of the generated file.
        "local __ok, __lib = pcall(function(...)",
        _read(OUT),
        "end)",
        "Uranium = __ok and __lib or nil",
        "LOAD_ERROR = (not __ok) and __lib or nil",
        _read(checks),
    ])
    with open(SMOKE_BUILD, "w", encoding="utf-8", newline="\n") as f:
        f.write(chunk)

    r = subprocess.run([tool, SMOKE_BUILD], capture_output=True)
    out = (r.stdout + r.stderr).decode("utf-8", "replace").strip()
    if r.returncode != 0:
        sys.exit(f"error: the bundle does not load\n{out}")
    print(out or "ok: smoke — bundle loads")
    os.remove(SMOKE_BUILD)  # kept on failure, so it can be run by hand
    return True


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


def brand_block():
    """The inner text of `Theme.Brand = { ... }`, braces excluded.

    Every scrape below is anchored to this rather than run over the whole of
    Theme.lua. They used to be file-wide `re.search`es, so the first match won:
    `\\bzoom\\s*=` picked up whichever `zoom` appeared earliest in the file, and
    adding an unrelated one to Theme.Metrics (above Brand) would have silently
    handed the standalone page the wrong crop for the brand mark. Every failure
    on this path is soft by design — which is exactly why a wrong answer would
    never announce itself."""
    src = _read(os.path.join(ROOT, "Theme.lua"))
    # Anchored to the ASSIGNMENT at column 0, not to the first mention of the
    # name: the comment block above it references `Theme.Brand.assets`, and a
    # plain `find` walked straight into the prose.
    at = re.search(r"^Theme\.Brand\s*=", src, re.M)
    brace = src.find("{", at.end()) if at else -1
    if brace == -1:
        sys.exit("error: couldn't find the Theme.Brand table in Theme.lua")
    depth = 0
    for i in range(brace, len(src)):
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
            if depth == 0:
                return src[brace + 1 : i]
    sys.exit("error: Theme.Brand's table is unterminated in Theme.lua")


def screen_brand():
    """Theme.Brand.name, for the standalone page's wordmark — same reason the
    palette is injected rather than retyped: this build has to keep saying what
    the library says it's called."""
    m = re.search(r'\bname\s*=\s*"([^"]+)"', brand_block())
    if not m:
        sys.exit("error: couldn't read Theme.Brand.name for the standalone page")
    return m.group(1)


def screen_mark():
    """The brand PNG's url, the disk path util/Asset.lua caches it at, and the
    zoom the holder crops it with.

    The standalone page fetches and caches the mark exactly the way the library
    does, so it has to agree with the library about all three or it downloads a
    second copy under a second name. The path is `Asset.CacheFolder` + a djb2
    hash of the url, so it's derived here rather than pasted: a pasted one goes
    stale silently the first time any input moves.

    Every failure here is soft — no logo url, an unreadable Asset.lua, a hashing
    scheme that has since changed — because the page degrades to the accent
    square + initial it drew before this existed. It must never fail the build.
    """
    try:
        theme = _read(os.path.join(ROOT, "Theme.lua"))
        # `ASSETS` is a file-level local by necessity; the other three are read
        # out of the Brand table itself so an unrelated `logo`/`zoom` elsewhere
        # in Theme.lua can't win the match (see brand_block).
        brand = brand_block()
        base = re.search(r'local ASSETS\s*=\s*"([^"]+)"', theme)
        logo = re.search(r"logo\s*=\s*\{\s*(?:ASSETS\s*\.\.\s*)?\"([^\"]+)\"", brand)
        zoom = re.search(r"\bzoom\s*=\s*([0-9.]+)", brand)
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
        return path, (float(zoom.group(1)) if zoom else 1.0), url
    except Exception as err:  # noqa: BLE001 — soft by design, see the docstring
        print(f"warn: no brand mark for the standalone page ({err}) — "
              "it will draw the fallback square")
        return "", 1.0, ""


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

    mark_path, mark_zoom, mark_url = screen_mark()
    values = {
        "MARK": f'local MARK, ZOOM, LOGO_URL = "{mark_path}", {mark_zoom:g}, "{mark_url}"',
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


# ── the API surface ──────────────────────────────────────────────────────────
# The public method list exists in four places: the source, DOCS.md, CLAUDE.md's
# "Public API surface" block, and example.loadstring.lua — which the docs call
# "the spec" but which nothing ever ran. Four hand-synced copies of one list is
# four copies that drift, and the one that drifts most expensively is DOCS.md,
# because that's the one consumers read.
#
# There is no Roblox runtime here to execute the demo against, so this is a
# static cross-check instead: pull the real surface out of the source, then ask
# whether the demo calls anything that no longer exists (a hard error — the demo
# is real code) and whether the docs name anything that no longer exists, or miss
# anything that does (warnings — prose matching is fuzzier than code).

# Method names in these files belong to Roblox, not to us.
ENGINE_METHODS = {
    "Connect", "Disconnect", "Wait", "Once", "Destroy", "Clone", "IsA",
    "GetService", "HttpGet", "HttpGetAsync", "JSONDecode", "JSONEncode",
    "FindFirstChild", "FindFirstChildOfClass", "FindFirstChildWhichIsA",
    "WaitForChild", "GetChildren", "GetDescendants", "GetPlayers",
    "GetAttribute", "SetAttribute", "GetPropertyChangedSignal",
    "GetUserThumbnailAsync", "CaptureFocus", "ReleaseFocus", "TweenSize",
    "Play", "Pause", "Stop", "Resume", "Lerp", "ToHex", "ToHSV", "Magnitude",
}

# Receivers whose methods are ours, as written in prose.
DOC_RECEIVERS = r"(?:Uranium|Window|window|Tab|tab|Group|Section|Hud|hud|Binding)"

# Stand-ins the docs use when the *shape* of a call is the point rather than any
# particular method ("every `Uranium:Method(...)` call throws…").
DOC_PLACEHOLDERS = {"Method", "Foo", "Something", "Whatever"}


def api_surface(mods):
    """Every method the library defines, as a flat set of names.

    Deliberately over-broad: this is used to answer "does this name exist at
    all", so a private helper sharing a name with a public method is a
    false negative (we say nothing) rather than a false alarm."""
    names = set()
    for src in mods.values():
        names |= set(re.findall(r"function\s+[\w.]+[:.](\w+)\s*\(", src))
        names |= set(re.findall(r"(\w+)\s*=\s*function\s*\(", src))
        names |= set(re.findall(r'\["(\w+)"\]\s*=\s*function\s*\(', src))
    return names


def api_check():
    """Cross-check the demo and the docs against the real surface."""
    demo_path = os.path.join(BASE, "example.loadstring.lua")
    docs_path = os.path.join(BASE, "DOCS.md")
    if not os.path.exists(demo_path):
        return

    # Read the tree from disk rather than reusing main()'s `mods`: LucideData has
    # been rewritten in that dict by now, and this wants the sources as written.
    mods = {}
    for dirpath, _, files in os.walk(ROOT):
        for f in files:
            if f.endswith(".lua"):
                mods[os.path.join(dirpath, f)] = _read(os.path.join(dirpath, f))
    surface = api_surface(mods)

    # 1. The demo is real code, so a call into a method that no longer exists is
    #    a genuine break — it would fail in the executor on the line it's on.
    demo = _read(demo_path)
    called = set(re.findall(r":([A-Z]\w+)\s*\(", demo)) - ENGINE_METHODS
    gone = sorted(called - surface)
    if gone:
        sys.exit(
            "error: example.loadstring.lua calls "
            + ", ".join(f":{n}()" for n in gone)
            + " — nothing in coreui/ defines "
            + ("them" if len(gone) > 1 else "it")
            + ".\n       The demo is the API's worked example; fix the call or "
              "restore the method."
        )
    print(f"ok: example.loadstring.lua — all {len(called)} API calls exist")

    # 2. The docs are prose, so both directions are advisory. Documented-but-gone
    #    is the one that actually misleads someone.
    if not os.path.exists(docs_path):
        return
    docs = _read(docs_path)
    documented = (set(re.findall(DOC_RECEIVERS + r":(\w+)", docs))
                  - ENGINE_METHODS - DOC_PLACEHOLDERS)
    stale = sorted(documented - surface)
    if stale:
        print("warn: DOCS.md documents "
              + ", ".join(f":{n}()" for n in stale)
              + " — no such method in coreui/")

    # Undocumented window methods, which is the list a consumer can't discover.
    # Matched as a bare `:Name`, not `Window:Name` — the reference tables pair
    # related methods on one row (`Window:GetAutoload()` / `:SetAutoload(name?)`)
    # and the second half of every one of those is written without a receiver.
    window_methods = set()
    for src in mods.values():
        window_methods |= set(re.findall(r"function\s+window:(\w+)\s*\(", src))
    undocumented = sorted(n for n in window_methods
                          if not re.search(r":" + n + r"\b", docs))
    if undocumented:
        print("warn: DOCS.md never mentions Window:"
              + ", Window:".join(undocumented))
    if not stale and not undocumented:
        print(f"ok: DOCS.md — {len(window_methods)} window methods all documented")


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
    if "--no-verify" in sys.argv:
        # An escape hatch for working without the toolchain, deliberately loud:
        # the whole point of the checks is that nothing reaches a commit unparsed.
        global verify, api_check, smoke
        verify = lambda _paths: (print("warn: --no-verify — build outputs NOT checked"), True)[1]
        api_check = lambda: None
        smoke = lambda: True
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

    # Verified BEFORE the mirror is written: ui/uibundle.lua is what the delivery
    # worker serves, so a bundle that doesn't parse must not reach it. The
    # canonical coreui.bundle.lua is already on disk at this point (nothing reads
    # it until it's committed, and push.py runs this script first), so a failure
    # here stops the push rather than shipping.
    complete = verify([OUT, UI_SCREEN])
    complete &= smoke()

    shutil.copyfile(OUT, UI_BUNDLE)
    print(f"wrote {UI_BUNDLE}  (mirror of coreui.bundle.lua)")

    # Mirrored after api_check has had a chance to complain about the source
    # DOCS.md, so what lands in ui/ is the copy that was just checked.
    api_check()
    docs_src = os.path.join(BASE, "DOCS.md")
    if os.path.isfile(docs_src):
        shutil.copyfile(docs_src, UI_DOCS)
        print(f"wrote {UI_DOCS}  (mirror of DOCS.md, {_kb(os.path.getsize(UI_DOCS))})")
    else:
        print("warn: DOCS.md not found — ui/DOCS.md was NOT refreshed")

    if not complete:
        print("\n** build NOT fully verified — install the Luau toolchain "
              "(`rokit add luau-lang/luau`) before pushing. **")


if __name__ == "__main__":
    main()
