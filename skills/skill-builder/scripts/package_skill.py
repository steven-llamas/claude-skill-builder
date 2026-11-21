#!/usr/bin/env python3
"""Validate, then zip a skill folder for upload to Claude.ai (Settings > Capabilities > Skills).

Usage: python package_skill.py PATH_TO_SKILL_FOLDER [OUTPUT_DIR]
Writes OUTPUT_DIR/skill-name.zip (default OUTPUT_DIR: the skill's parent folder).
The zip contains the skill folder at its root. Excludes evals/, __pycache__/,
node_modules/, *.pyc, and dotfiles, matching Anthropic's packager.
Standard library only.
"""
import fnmatch
import os
import subprocess
import sys
import zipfile

EXCLUDE_DIRS = {"__pycache__", "node_modules"}
ROOT_EXCLUDE_DIRS = {"evals"}  # test data stays out of the shipped skill
EXCLUDE_GLOBS = ("*.pyc", ".*")


def main():
    if len(sys.argv) not in (2, 3):
        print(__doc__)
        return 2
    skill = os.path.abspath(os.path.expanduser(sys.argv[1]))
    out_dir = os.path.abspath(os.path.expanduser(sys.argv[2])) if len(sys.argv) == 3 else os.path.dirname(skill)
    validator = os.path.join(os.path.dirname(os.path.abspath(__file__)), "validate_skill.py")

    result = subprocess.run([sys.executable, "-I", validator, skill])
    if result.returncode != 0:
        print("Packaging stopped: fix the validation errors above first.")
        return 1

    name = os.path.basename(skill)
    os.makedirs(out_dir, exist_ok=True)
    zip_path = os.path.join(out_dir, name + ".zip")
    count = 0
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for root, dirs, files in os.walk(skill):
            rel_root = os.path.relpath(root, skill)
            dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS and not d.startswith(".")
                       and not (rel_root == "." and d in ROOT_EXCLUDE_DIRS)]
            for fn in files:
                if any(fnmatch.fnmatch(fn, g) for g in EXCLUDE_GLOBS):
                    continue
                full = os.path.join(root, fn)
                if os.path.abspath(full) == zip_path:
                    continue
                arc = os.path.join(name, os.path.relpath(full, skill)).replace(os.sep, "/")
                zf.write(full, arc)
                count += 1
    print(f"Packaged {count} files into {zip_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
