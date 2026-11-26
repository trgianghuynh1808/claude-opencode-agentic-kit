#!/usr/bin/env python3
"""adopt_plan_files: /ship commits a board task's leftover plan file on staging, and leaves everything else alone.

Loads scripts/room-ops.py by path, builds a temp git repo on `staging` and checks four cases:
a plan of a board task (committed), a plan of an unknown task (left), a non-plan file (left), another branch (nothing).

Run: python3 -I tools/test-ship-leftover-plan.py  (exit 0 = pass)
"""
import importlib.util
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def sh(*a):
    subprocess.run(["git", *a], check=True, capture_output=True)


def main():
    spec = importlib.util.spec_from_file_location("room_ops_ship_mod", os.path.join(ROOT, "scripts", "room-ops.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.tasks = lambda lines: [{"slug": "task-22-abc"}]
    with tempfile.TemporaryDirectory() as d:
        os.chdir(d)
        sh("init", "-q", "-b", "staging")
        sh("config", "user.email", "t@t")
        sh("config", "user.name", "t")
        sh("commit", "-q", "--allow-empty", "-m", "init")
        os.makedirs(f"{mod.AG}/tasks")
        mine = f"{mod.AG}/tasks/2026-11-26-task-22-abc.md"
        orphan = f"{mod.AG}/tasks/2026-11-26-task-99-zzz.md"
        for p in (mine, orphan, "notes.txt"):
            open(p, "w").write("x")
        sh("checkout", "-q", "-b", "other")
        assert mod.adopt_plan_files([], "staging") == [], "must do nothing off the staging branch"
        sh("checkout", "-q", "staging")
        assert mod.adopt_plan_files([], "staging") == [mine], "board task plan must be committed"
        st = subprocess.run(["git", "status", "--porcelain"], capture_output=True, text=True).stdout
        assert orphan in st and "notes.txt" in st, "orphan plan and non-plan file stay untouched"
        assert mine not in st, "adopted plan is no longer dirty"
    print("ok")


if __name__ == "__main__":
    try:
        main()
    except AssertionError as e:
        print(f"FAIL: {e}")
        sys.exit(1)
