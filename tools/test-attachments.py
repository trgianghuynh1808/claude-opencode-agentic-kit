#!/usr/bin/env python3
"""Pictures sent with /task and /revise: copied to attachments/<id>/, only from inbox/files, removed at ship and /clear.
Run: python3 -I tools/test-attachments.py  (exit 0 = pass)"""
import importlib.util, os, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location("room_ops_mod", os.path.join(ROOT, "scripts", "room-ops.py"))
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

bad = []
def check(name, ok):
    print(("  ✓ " if ok else "  ✗ ") + name)
    if not ok:
        bad.append(name)

with tempfile.TemporaryDirectory() as tmp:
    os.chdir(tmp)
    mod.AG = ".agents"
    mod.ATTACH_DIR = ".agents/attachments"
    os.makedirs(".agents/inbox/files")
    for n in ("1-1.jpg", "1-2.png", "1-3.txt"):
        open(f".agents/inbox/files/{n}", "wb").write(b"x")
    open("secret.png", "wb").write(b"s")

    out = mod.attach_images("T07", [".agents/inbox/files/1-1.jpg", ".agents/inbox/files/1-2.png"])
    check("copies pictures to attachments/<id>/req-N.ext", out == [".agents/attachments/T07/req-1.jpg", ".agents/attachments/T07/req-2.png"] and all(os.path.isfile(p) for p in out))
    check("tag is used for revise pictures", mod.attach_images("T07", [".agents/inbox/files/1-1.jpg"], tag="rev-0930")[0].endswith("rev-0930-1.jpg"))
    check("a path outside inbox/files is refused", mod.attach_images("T08", ["secret.png", "../secret.png", ".agents/inbox/files/../../secret.png"]) == [])
    check("a non-image extension is refused", mod.attach_images("T08", [".agents/inbox/files/1-3.txt"]) == [])
    check("a missing file is skipped", mod.attach_images("T08", [".agents/inbox/files/none.png"]) == [])
    check("task_attachments lists them", len(mod.task_attachments("T07")) == 3)

    mod.drop_inbox_images([".agents/inbox/files/1-1.jpg", "secret.png"])
    check("drop removes inbox pictures only", not os.path.exists(".agents/inbox/files/1-1.jpg") and os.path.exists("secret.png"))

sys.exit(1 if bad else 0)
