#!/usr/bin/env python3
"""plan_touches_env: the plan check blocks real .env edits, not plans that only mention .env.

Run: python3 -I tools/test-check-plan-env.py  (exit 0 = pass)
"""
import importlib.util
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location("room_ops_env_mod", os.path.join(ROOT, "scripts", "room-ops.py"))
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

CASES = [
    ("step edits .env", "## Plan\n- [ ] 1. [dễ] sửa `.env` thêm KEY", True),
    ("step creates .env.local", "## Plan\n- [ ] 1. [dễ] tạo .env.local", True),
    ("step promises not to touch .env", "## Plan\n- [ ] 1. [dễ] README, KHÔNG tạo/sửa file `.env*`", False),
    ("context says where env lives", "## Quyết định\n- env nằm trong `.env.local`\n## Plan\n- [ ] 1. [dễ] đọc import.meta.env", False),
    ("only .env.example", "## Plan\n- [ ] 1. [dễ] đọc .env.example", False),
    ("no Plan heading: whole text", "- [ ] 1. sửa .env", True),
]
bad = [n for n, t, want in CASES if mod.plan_touches_env(t) != want]
if bad:
    print("FAIL:", ", ".join(bad))
    sys.exit(1)
print("ok")
