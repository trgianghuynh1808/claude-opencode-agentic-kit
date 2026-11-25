#!/usr/bin/env python3
"""Helpers for the `kit` command (kit maintenance only, not installed into projects).

  kit-lib.py rooms [name|path]            TSV of registered rooms: name, path, topic
  kit-lib.py check <topic> <port> <path>  exit 2 if the topic belongs to another project; prints a warning if the port is shared
  kit-lib.py patch-claude <project>       add/replace the AUTO_MODE section of CLAUDE.md -> "changed" | "unchanged"
  kit-lib.py ensure-env <project>         add missing keys to .agents/room.env -> the keys that were added
  kit-lib.py detect-port <project>        guess the dev server port from package.json
  kit-lib.py status                       table of every room
  kit-lib.py scan [dir] [--unregistered]  find folders that carry kit files (registered or not)
  kit-lib.py unregister <name|path>       remove a room from the registry
"""
import json
import os
import re
import subprocess
import sys

KIT_DIR = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
REGISTRY = os.environ.get("AGENT_ROOMS_FILE") or os.path.join(KIT_DIR, "bridge-bot", "rooms.json")

ENV_DEFAULTS = [
    ("MODEL_MANAGER", "", "# Model theo vai (alias haiku | sonnet | opus hoặc id đầy đủ). Trống = mặc định của claude CLI."),
    ("MODEL_TECHLEAD", "", None),
    ("MAX_TURNS_MANAGER", "20", "# Giới hạn số lượt mỗi lần gọi (chặn một lần chạy lạc đốt quota)"),
    ("MAX_TURNS_TECHLEAD", "150", None),
    ("MAX_TURNS_PLAN", "40", "# Chế độ /plan (Tech Lead đọc repo để trả lời câu hỏi): giới hạn số lượt"),
    ("AUTO_SPLIT", "lines", '# /auto tách task: "lines" (mỗi dòng một task, không tốn Claude) hoặc "claude" (Manager tách)'),
    ("KEEP_SHIPPED", "5", "# Sau /ship, giữ lại bao nhiêu task đã ship gần nhất trên board"),
    ("CHAT_WITH_CLAUDE", "false", '# Tin thường (không có lệnh): "false" = trả lời mẫu, "true" = để Claude Manager trả lời (tốn quota)'),
]


def load_rooms():
    try:
        with open(REGISTRY, encoding="utf8") as f:
            return json.load(f).get("rooms", [])
    except (OSError, ValueError):
        return []


def read_env(project):
    out = {}
    try:
        with open(os.path.join(project, ".agents", "room.env"), encoding="utf8") as f:
            for line in f:
                m = re.match(r'^([A-Z_][A-Z0-9_]*)="?([^"\n]*)"?\s*$', line)
                if m:
                    out[m.group(1)] = m.group(2)
    except OSError:
        pass
    return out


def cmd_rooms(flt=None):
    for r in load_rooms():
        if flt and flt not in (r.get("name"), r.get("path"), os.path.basename(r.get("path", ""))):
            continue
        print(f"{r.get('name')}\t{r.get('path')}\t{r.get('topicId')}")
    return 0


def cmd_check(topic, port, path):
    path = os.path.realpath(path)
    for r in load_rooms():
        other = os.path.realpath(r.get("path", ""))
        if str(r.get("topicId")) == str(topic) and other != path:
            print(f"Topic {topic} đã thuộc về phòng '{r.get('name')}' ({other})")
            return 2
    for r in load_rooms():
        other = os.path.realpath(r.get("path", ""))
        if other != path and read_env(other).get("APP_PORT") == str(port):
            print(f"Port {port} cũng đang được phòng '{r.get('name')}' dùng, hai dev server sẽ đụng nhau")
    return 0


def kit_template_section():
    with open(os.path.join(KIT_DIR, "template", "CLAUDE.md"), encoding="utf8") as f:
        tpl = f.read()
    return tpl[tpl.index("## AUTO_MODE"):].rstrip("\n") + "\n"


def cmd_patch_claude(project):
    path = os.path.join(project, "CLAUDE.md")
    sec = kit_template_section()
    if not os.path.exists(path):
        print("unchanged")  # install.sh creates it from the template
        return 0
    with open(path, encoding="utf8") as f:
        cur = f.read()
    if "## AUTO_MODE" in cur:
        i = cur.index("## AUTO_MODE")
        j = cur.find("\n## ", i + 1)
        new = cur[:i] + sec + ("\n" + cur[j + 1:] if j != -1 else "")
    else:
        new = cur.rstrip("\n") + "\n\n" + sec
    if new == cur:
        print("unchanged")
        return 0
    with open(path, "w", encoding="utf8") as f:
        f.write(new)
    print("changed")
    return 0


def cmd_ensure_env(project):
    path = os.path.join(project, ".agents", "room.env")
    if not os.path.exists(path):
        return 0
    have = read_env(project)
    add = []
    block = []
    for key, default, comment in ENV_DEFAULTS:
        if key in have:
            continue
        if comment:
            block.append(comment)
        block.append(f'{key}="{default}"')
        add.append(key)
    if add:
        with open(path, encoding="utf8") as f:
            text = f.read()
        with open(path, "w", encoding="utf8") as f:
            f.write(text.rstrip("\n") + "\n" + "\n".join(block) + "\n")
        print(" ".join(add))
    return 0


def cmd_detect_port(project):
    try:
        with open(os.path.join(project, "package.json"), encoding="utf8") as f:
            pkg = json.load(f)
    except (OSError, ValueError):
        return 0
    deps = {**pkg.get("dependencies", {}), **pkg.get("devDependencies", {})}
    scripts = " ".join(str(v) for v in pkg.get("scripts", {}).values())
    m = re.search(r"--port[ =](\d+)|-p[ =](\d+)", scripts)
    if m:
        print(m.group(1) or m.group(2))
    elif "vite" in deps:
        print(5173)
    elif "next" in deps or "react-scripts" in deps:
        print(3000)
    elif "@angular/cli" in deps:
        print(4200)
    return 0


def tmux_has(name):
    try:
        return subprocess.run(["tmux", "has-session", "-t", f"room-{name}"], capture_output=True).returncode == 0
    except OSError:
        return False


def kit_version():
    try:
        v = subprocess.run(["git", "-C", KIT_DIR, "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()
        return v or "?"
    except OSError:
        return "?"


def cmd_status():
    rooms = load_rooms()
    if not rooms:
        print("Chưa có phòng nào. Thêm bằng: kit new <tên> hoặc kit add <đường dẫn>")
        return 0
    cur = kit_version()
    rows = [("PHÒNG", "TOPIC", "CHẠY", "TỰ ĐỘNG", "ĐANG LÀM", "KIT")]
    for r in rooms:
        path, name = r.get("path", ""), r.get("name", "?")
        if not os.path.isdir(path):
            rows.append((name, str(r.get("topicId")), "-", "-", "thư mục không còn tồn tại", "-"))
            continue
        env = read_env(path)
        running = "chạy" if tmux_has(name) else "dừng"
        task = "-"
        try:
            with open(os.path.join(path, ".agents", "board.md"), encoding="utf8") as f:
                for line in f:
                    m = re.match(r"^- \[ \] `(T\d+)` \[(\w+)\] (.*?) \(slug:", line)
                    if m:
                        task = f"{m.group(1)} [{m.group(2)}] {m.group(3)[:38]}"
                        break
        except OSError:
            pass
        try:
            with open(os.path.join(path, ".agents", "kit-version"), encoding="utf8") as f:
                ver = f.read().strip()
        except OSError:
            ver = "?"
        mark = ver if ver == cur else f"{ver} (cũ, kit là {cur})"
        rows.append((name, str(r.get("topicId")), running, "BẬT" if env.get("AUTO_MODE") == "true" else "tắt", task, mark))
    widths = [max(len(row[i]) for row in rows) for i in range(len(rows[0]))]
    for row in rows:
        print("  ".join(cell.ljust(widths[i]) for i, cell in enumerate(row)).rstrip())
    return 0


def cmd_unregister(key):
    rooms = load_rooms()
    keep = [r for r in rooms if key not in (r.get("name"), r.get("path"), os.path.basename(r.get("path", "")))]
    if len(keep) == len(rooms):
        print("không thấy phòng nào khớp")
        return 1
    tmp = REGISTRY + ".tmp"
    with open(tmp, "w", encoding="utf8") as f:
        json.dump({"rooms": keep}, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, REGISTRY)
    print(f"đã gỡ {len(rooms) - len(keep)} phòng khỏi registry")
    return 0


def cmd_scan(*args):
    only_unreg = "--unregistered" in args
    pos = [a for a in args if not a.startswith("--")]
    root = os.path.realpath(pos[0]) if pos else os.path.expanduser("~/Documents/projects")
    registered = {os.path.realpath(r.get("path", "")) for r in load_rooms()}
    cur = kit_version()
    rows = []
    for name in sorted(os.listdir(root)) if os.path.isdir(root) else []:
        p = os.path.join(root, name)
        if not os.path.isdir(p) or os.path.realpath(p) == KIT_DIR:
            continue
        has_room = os.path.exists(os.path.join(p, ".agents", "room.env"))
        legacy = os.path.exists(os.path.join(p, ".agents", "config.sh")) or os.path.exists(os.path.join(p, "scripts", "run-task.sh"))
        if not (has_room or legacy):
            continue
        reg = os.path.realpath(p) in registered
        if only_unreg and reg:
            continue
        try:
            with open(os.path.join(p, ".agents", "kit-version"), encoding="utf8") as f:
                ver = f.read().strip()
        except OSError:
            ver = "?"
        if reg:
            kind, hint = "phòng (đã đăng ký)", "kit upgrade " + name
        elif has_room:
            kind, hint = "có phòng, chưa đăng ký bridge", "cd " + p + " && scripts/agent-room.sh init --topic <ID> --port <PORT>"
        else:
            kind, hint = "kit chế độ cũ (chưa có phòng)", "kit add " + p + " --port <PORT> --topic <ID>"
        rows.append((name, kind, ver if ver == cur else f"{ver} (cũ)", hint))
    if not rows:
        print("Không có project nào dùng kit" + (" mà chưa đăng ký" if only_unreg else "") + f" trong {root}")
        return 0
    rows.insert(0, ("PROJECT", "LOẠI", "KIT", "GỢI Ý"))
    widths = [max(len(r[i]) for r in rows) for i in range(3)]
    for r in rows:
        print("  ".join(r[i].ljust(widths[i]) for i in range(3)) + "  " + r[3])
    return 0


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    c, a = argv[1], argv[2:]
    table = {"rooms": cmd_rooms, "check": cmd_check, "patch-claude": cmd_patch_claude, "ensure-env": cmd_ensure_env,
             "detect-port": cmd_detect_port, "status": cmd_status, "unregister": cmd_unregister, "scan": cmd_scan}
    if c not in table:
        print(__doc__)
        return 1
    return table[c](*a)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
