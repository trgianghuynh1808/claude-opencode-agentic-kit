#!/usr/bin/env python3
"""Ship report timing: phase durations come from .agents/timeline/<slug>.log (plan / code / verify), the block lists start, end and total.
Run: python3 -I tools/test-ship-timeline.py  (exit 0 = pass)"""
import importlib.util, os, sys, tempfile
from datetime import datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location("room_ops_mod", os.path.join(ROOT, "scripts", "room-ops.py"))
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

bad = []
def check(name, ok):
    print(("  ✓ " if ok else "  ✗ ") + name)
    if not ok:
        bad.append(name)

T0 = int(datetime(2026, 11, 25, 20, 19, 0).timestamp())
def write(tmp, slug, events):
    os.makedirs(f"{tmp}/timeline", exist_ok=True)
    with open(f"{tmp}/timeline/{slug}.log", "w") as f:
        f.write("\n".join(f"{T0 + off} {ev}" for off, ev in events) + "\n")

check("durations format", [mod.fmt_dur(s) for s in (5, 65, 3725)] == ["5s", "1m 05s", "1h 02m"])

with tempfile.TemporaryDirectory() as tmp:
    mod.AG = tmp
    # plan 60s, user wait 90s before the hand-off, code 600s, verify 120s, then a fix cycle: code 300s + verify 60s
    write(tmp, "s-ok", [(0, "plan_start"), (60, "plan_end"), (150, "code_start"), (750, "code_end"), (760, "finish_start"), (880, "finish_end")])
    tl = mod.task_timeline("s-ok")
    check("plan / wait / code / verify / total", tl and (tl["plan"], tl["wait"], tl["code"], tl["verify"], tl["total"], tl["fixes"]) == (60, 90, 600, 120, 880, 0))
    write(tmp, "s-fix", [(0, "plan_start"), (60, "plan_end"), (65, "code_start"), (365, "code_end"), (370, "finish_start"), (400, "finish_end"),
                         (410, "code_start"), (710, "code_end"), (715, "finish_start"), (775, "finish_end")])
    tl = mod.task_timeline("s-fix")
    check("fix cycle adds code + verify and counts 1 fix", tl and (tl["code"], tl["verify"], tl["fixes"], tl["total"]) == (600, 90, 1, 775))
    check("no timeline file -> None", mod.task_timeline("missing") is None)
    block = mod.timeline_block([{"id": "T12", "slug": "s-ok"}, {"id": "T13", "slug": "s-fix"}, {"id": "T01", "slug": "missing"}])
    check("block has header, task ids, start → end", "⏱ **Thời gian**" in block and "**T12**" in block and "20:19 → 20:33" in block)
    check("block shows each phase and the user wait", "Plan 1m 00s (+ chờ bạn 1m 30s)" in block and "Code 10m 00s" in block and "Test/Verify 2m 00s" in block)
    check("block shows the fix cycle and the batch range", "1 vòng sửa" in block and "Cả đợt:" in block)
    check("a task without timeline is simply left out", "T01" not in block)
    check("nothing recorded -> empty block", mod.timeline_block([{"id": "T01", "slug": "missing"}]) == "")
sys.exit(1 if bad else 0)
