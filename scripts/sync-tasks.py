#!/usr/bin/env python3
"""Sync task gate scripts between scripts/tasks/*.sh and the task .md files.

The .sh files under scripts/tasks/ are the CANONICAL source — edit and test
them there (see scripts/test/). The NanoClaw template format requires the
script inline in each task's frontmatter (`script: |`), so this tool injects
each .sh into its matching .md.

Usage:
    python3 scripts/sync-tasks.py           # inject .sh -> .md (write)
    python3 scripts/sync-tasks.py --check   # verify .md matches .sh (CI mode)

Mapping: scripts/tasks/<group>/<name>.sh -> <group-dir>/ai.nanoco.nanoclaw/tasks/<name>.md
"""
import re
import sys
import glob
import os

GROUPS = {
    "support": "support/community-support",
    "engineering": "engineering/community-coding",
    "marketing": "marketing/community-marketing",
}

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def md_path_for(sh_path):
    rel = os.path.relpath(sh_path, os.path.join(ROOT, "scripts", "tasks"))
    group, name = rel.split(os.sep, 1)
    return os.path.join(ROOT, GROUPS[group], "ai.nanoco.nanoclaw", "tasks",
                        name[:-3] + ".md")


def split_md(text):
    m = re.match(r"---\n(.*?\n)---\n(.*)", text, re.S)
    if not m:
        raise ValueError("no frontmatter")
    return m.group(1), m.group(2)


def extract_script(front):
    m = re.search(r"^script: \|\n((?:  .*\n|\n)*)", front, re.M)
    if not m:
        return None, front
    body = "\n".join(l[2:] if l.startswith("  ") else ""
                     for l in m.group(1).split("\n")).rstrip() + "\n"
    return body, front


def inject_script(front, script):
    indented = "".join(("  " + l).rstrip() + "\n" if l else "\n"
                       for l in script.rstrip("\n").split("\n"))
    replacement = "script: |\n" + indented
    if re.search(r"^script: \|\n", front, re.M):
        # lambda replacement: script content contains backslash sequences
        # (printf '\n') that re.sub would otherwise interpret as escapes.
        return re.sub(r"^script: \|\n(?:  .*\n|\n)*", lambda m: replacement,
                      front, count=1, flags=re.M)
    return front.rstrip("\n") + "\n" + replacement


def main():
    check = "--check" in sys.argv
    fail = 0
    for sh in sorted(glob.glob(os.path.join(ROOT, "scripts", "tasks", "*", "*.sh"))):
        md = md_path_for(sh)
        if not os.path.exists(md):
            print(f"MISSING task file for {os.path.relpath(sh, ROOT)}: {os.path.relpath(md, ROOT)}")
            fail += 1
            continue
        want = open(sh).read().rstrip("\n") + "\n"
        text = open(md).read()
        front, body = split_md(text)
        have, _ = extract_script(front)
        if check:
            if have != want:
                print(f"DRIFT: {os.path.relpath(md, ROOT)} does not match {os.path.relpath(sh, ROOT)}")
                fail += 1
            continue
        new_front = inject_script(front, want)
        open(md, "w").write("---\n" + new_front + "---\n" + body)
        print(f"synced {os.path.relpath(md, ROOT)}")
    # Also flag any .md with an embedded script but no canonical .sh file.
    known_md = {md_path_for(sh) for sh in glob.glob(os.path.join(ROOT, "scripts", "tasks", "*", "*.sh"))}
    for md in sorted(glob.glob(os.path.join(ROOT, "*", "*", "ai.nanoco.nanoclaw", "tasks", "*.md"))):
        front, _ = split_md(open(md).read())
        script, _ = extract_script(front)
        if script and os.path.abspath(md) not in {os.path.abspath(p) for p in known_md}:
            print(f"ORPHAN embedded script (no .sh source): {os.path.relpath(md, ROOT)}")
            fail += 1
    if check and fail == 0:
        print("check OK: all task scripts match their .sh sources")
    sys.exit(1 if fail else 0)


if __name__ == "__main__":
    main()
