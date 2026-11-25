#!/usr/bin/env python3
"""The 'Phần còn lại' report shows only what exists (no empty Commit/Test sections); a finished step keeps its honest 'none yet' lines.
Run: python3 -I tools/test-leftover-report.py  (exit 0 = pass)"""
import importlib.util, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location("room_ops_mod", os.path.join(ROOT, "scripts", "room-ops.py"))
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

bad = []
def check(name, ok):
    print(("  ✓ " if ok else "  ✗ ") + name)
    if not ok:
        bad.append(name)

left = mod.step_report("s", 2, [], [], [], False, ["a note"])
check("leftover: no empty Commit section", "Commit" not in left)
check("leftover: no empty test section", "Kết quả test" not in left)
check("leftover: note kept", "a note" in left)
left2 = mod.step_report("s", 2, [], [("abc1234", "feat: x")], [("T1", "PASS")], False)
check("leftover with data shows Commit and tests", "abc1234" in left2 and "T1" in left2)
step = mod.step_report("s", 2, [(1, True, "vừa", "do x")], [], [], False)
check("finished step keeps its 'none yet' lines", "chưa có commit mới" in step and "chưa có test nào" in step)
sys.exit(1 if bad else 0)
