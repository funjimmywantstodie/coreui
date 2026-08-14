#!/usr/bin/env python3
"""
bundle.py — combine the coreui/ ModuleScript tree into a single loadstring-able
Lua file.

Roblox's require(script.Parent.X) needs a real instance tree. loadstring() only
runs one source chunk, so we flatten every module into one file and emulate
require() with an in-file module registry.

Usage:  python3 bundle.py  ->  writes coreui.bundle.lua
"""
import os, re, sys, subprocess
from datetime import datetime

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "coreui")
OUT  = os.path.join(os.path.dirname(os.path.abspath(__file__)), "coreui.bundle.lua")


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
EXTRA_ICONS: set = set()

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
    out = [
        "-- Uranium (bundled for loadstring) — generated by bundle.py, do not edit by hand.",
        f'-- build: {version}',
        f'print("[Uranium] build {version} loaded")',
        "local __modules, __cache = {}, {}",
        "local function __require(k)",
        "    local c = __cache[k]; if c then return c[1] end",
        "    local f = __modules[k]; if not f then error('Uranium: missing module '..k, 2) end",
        "    local v = f(); __cache[k] = { v }; return v",
        "end",
        "",
    ]
    for key, src in sorted(mods.items()):
        # rewrite every require(script...) to __require("resolved.key")
        def sub(m):
            return f'__require("{resolve(m.group(1), key)}")'
        src = REQ.sub(sub, src)
        out.append(f'__modules[{key!r}] = function()')
        out.append(src)
        out.append("end")
        out.append("")
    out.append('return __require("")')  # root = init.lua, returns the library table

    before = os.path.getsize(OUT) if os.path.exists(OUT) else 0
    open(OUT, "w", encoding="utf-8").write("\n".join(out))
    after = os.path.getsize(OUT)
    print(f"wrote {OUT}  ({len(mods)} modules, build {version})")
    print(f"size: {_kb(before)} -> {_kb(after)}  ({_delta(after - before)})")


if __name__ == "__main__":
    main()
