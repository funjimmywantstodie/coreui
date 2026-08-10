#!/usr/bin/env python3
"""push.py — bundle, commit, push, and copy a cache-proof (commit-pinned) loader
to the clipboard for instant in-executor testing.

    python3 push.py "optional commit message"

Why commit-pinned: raw.githubusercontent.com caches each *path* on a CDN for
~5 min and ignores ?query busters, so the branch URL (…/main/…) goes stale.
A per-commit URL (…/<sha>/…) is a brand-new path every push → never stale.
"""
import os
import platform
import shutil
import subprocess
import sys

REPO_RAW = "https://raw.githubusercontent.com/funjimmywantstodie/coreui"
BRANCH_URL = f"{REPO_RAW}/refs/heads/main/coreui.bundle.lua"


def run(cmd, **kwargs):
    """Run a command, raising on failure (like `set -e`)."""
    return subprocess.run(cmd, check=True, **kwargs)


def copy_to_clipboard(text: str) -> bool:
    """Best-effort clipboard copy on macOS / Windows / Linux. Returns True on success
    so the caller can fall back to just printing the URL instead of crashing the push."""
    system = platform.system()
    try:
        if system == "Darwin":
            subprocess.run(["pbcopy"], input=text, text=True, check=True)
            return True
        if system == "Windows":
            # clip.exe reads raw console-codepage bytes on stdin; UTF-16LE (no BOM) is
            # what actually round-trips non-ASCII (em dashes, curly quotes) correctly.
            subprocess.run(["clip"], input=text.encode("utf-16-le"), check=True)
            return True
        # Linux/BSD: no single standard tool — try the common ones in order.
        for cmd in (["wl-copy"], ["xclip", "-selection", "clipboard"], ["xsel", "--clipboard", "--input"]):
            if shutil.which(cmd[0]):
                subprocess.run(cmd, input=text, text=True, check=True)
                return True
        return False
    except (subprocess.CalledProcessError, FileNotFoundError, OSError):
        return False


def main():
    msg = sys.argv[1] if len(sys.argv) > 1 else "update bundle"

    # Work from the script's own directory.
    os.chdir(os.path.dirname(os.path.abspath(__file__)))

    run([sys.executable, "bundle.py"])

    run(["git", "add", "-A"])
    # git diff --cached --quiet exits 1 when there are staged changes.
    staged = subprocess.run(["git", "diff", "--cached", "--quiet"]).returncode
    if staged == 0:
        print("no changes to commit — reusing current HEAD")
    else:
        run(["git", "commit", "-m", msg])
        run(["git", "push"])

    sha = run(["git", "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
    raw = f"{REPO_RAW}/{sha}/coreui.bundle.lua"

    # Copy the demo with the branch URL swapped for the immutable commit URL.
    with open("example.loadstring.lua", encoding="utf-8") as f:
        demo = f.read().replace(BRANCH_URL, raw)

    print(f"pushed @ {sha[:7]}")
    if copy_to_clipboard(demo):
        print("commit-pinned demo copied to clipboard — paste into your executor (always fresh).")
    else:
        print("couldn't reach a clipboard tool (need pbcopy / clip / wl-copy / xclip / xsel) — copy manually:")
        print(demo)
    print(f"raw: {raw}")


if __name__ == "__main__":
    main()
