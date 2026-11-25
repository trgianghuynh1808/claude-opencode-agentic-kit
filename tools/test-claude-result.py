#!/usr/bin/env python3
"""claude-result: parses both `--output-format json` and the stream-json event stream; the stream also yields the tool calls
(which files the model read) that go to logs/tools.log and the usage.log row.
Run: python3 -I tools/test-claude-result.py  (exit 0 = pass)"""
import importlib.util, io, json, os, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location("room_ops_mod", os.path.join(ROOT, "scripts", "room-ops.py"))
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

bad = []
def check(name, ok):
    print(("  ✓ " if ok else "  ✗ ") + name)
    if not ok:
        bad.append(name)

result = {"type": "result", "subtype": "success", "is_error": False, "result": "xong", "num_turns": 3, "total_cost_usd": 0.1,
          "usage": {"input_tokens": 1, "output_tokens": 2, "cache_read_input_tokens": 3, "cache_creation_input_tokens": 4}}
stream = "\n".join(json.dumps(e) for e in [
    {"type": "system", "subtype": "init"},
    {"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "Read", "input": {"file_path": "/p/CLAUDE.md"}},
                                                  {"type": "tool_use", "name": "Grep", "input": {"pattern": "foo", "path": "src"}}]}},
    {"type": "assistant", "message": {"content": [{"type": "text", "text": "hi"}, {"type": "tool_use", "name": "Bash", "input": {"command": "npm run typecheck"}}]}},
    {"type": "user", "message": {}}, result])

d, tools = mod.parse_claude_output(stream)
check("stream: result event found", d and d["result"] == "xong")
check("stream: tool calls listed in order", tools == [("Read", "/p/CLAUDE.md"), ("Grep", "foo src"), ("Bash", "npm run typecheck")])
d2, t2 = mod.parse_claude_output(json.dumps(result))
check("plain json still works, no tools", d2["result"] == "xong" and t2 == [])
check("plain text -> (None, [])", mod.parse_claude_output("just text") == (None, []))

with tempfile.TemporaryDirectory() as tmp:
    mod.USAGE_LOG = os.path.join(tmp, "logs", "usage.log")
    sys.stdin = io.StringIO(stream)
    out = io.StringIO(); old, sys.stdout = sys.stdout, out
    rc = mod.cmd_claude_result("techlead", "T1 lên plan", "sonnet")
    sys.stdout = old
    check("exit 0 and text printed", rc == 0 and out.getvalue().strip() == "xong")
    row = json.loads(open(mod.USAGE_LOG).read().splitlines()[-1])
    check("usage row has tool counts", row["tools"] == {"Read": 1, "Grep": 1, "Bash": 1} and row["turns"] == 3)
    log = open(os.path.join(tmp, "logs", "tools.log")).read()
    check("tools.log lists the file that was read", "Read   /p/CLAUDE.md" in log and "T1 lên plan" in log)
sys.exit(1 if bad else 0)
