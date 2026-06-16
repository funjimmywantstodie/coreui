#!/usr/bin/env python3
"""push.py — bundle, commit, push, and copy a cache-proof (commit-pinned) loader
to the clipboard for instant in-executor testing.

    python3 push.py "optional commit message"

Why commit-pinned: raw.githubusercontent.com caches each *path* on a CDN for
~5 min and ignores ?query busters, so the branch URL (…/main/…) goes stale.
A per-commit URL (…/<sha>/…) is a brand-new path every push → never stale.
"""
import os
import subprocess
import sys

REPO_RAW = "https://raw.githubusercontent.com/funjimmywantstodie/coreui"
BRANCH_URL = f"{REPO_RAW}/refs/heads/main/coreui.bundle.lua"


def run(cmd, **kwargs):
    """Run a command, raising on failure (like `set -e`)."""
    return subprocess.run(cmd, check=True, **kwargs)


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
    with open("example.loadstring.lua") as f:
        demo = f.read().replace(BRANCH_URL, raw)
    subprocess.run(["pbcopy"], input=demo, text=True, check=True)

    print(f"pushed @ {sha[:7]}")
    print("commit-pinned demo copied to clipboard — paste into your executor (always fresh).")
    print(f"raw: {raw}")


if __name__ == "__main__":
    main()
