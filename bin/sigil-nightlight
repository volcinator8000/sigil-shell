#!/usr/bin/env python3
"""Night light control on top of the hyprsunset schedule.
Usage: nightlight.sh on|off|toggle|state|reset|autostart|schedule-state
State = manual override (runtime file) if one was made since the last schedule
boundary, otherwise whatever the schedule says for the current time."""
import os, re, sys, subprocess, time
CONF = os.path.expanduser("~/.config/hypr/hyprsunset.conf")
STATE = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "nightlight")

NIGHT = {"gamma": 100}
def schedule():
    """(start, end, night_temp); also fills NIGHT["gamma"] and the enabled flag"""
    start, end, temp = 21 * 60, 7 * 60 + 30, 4200
    try:
        text = open(CONF).read()
    except OSError:
        return start, end, temp
    NIGHT["enabled"] = not re.search(r"^#\s*schedule\s*=\s*off", text, re.M)
    blocks = re.findall(r"profile\s*\{(.*?)\}", text, re.S)
    temps = [(re.search(r"temperature\s*=\s*(\d+)", b), b) for b in blocks]
    # the night profile is the one with the lowest temperature; the other is day (identity or warmer)
    night_block = min((b for m, b in temps if m), key=lambda b: int(re.search(r"temperature\s*=\s*(\d+)", b).group(1)), default=None)
    for block in blocks:
        t = re.search(r"time\s*=\s*(\d+):(\d+)", block)
        if not t:
            continue
        mins = int(t.group(1)) * 60 + int(t.group(2))
        if block is night_block:
            start = mins
            temp = int(re.search(r"temperature\s*=\s*(\d+)", block).group(1))
            g = re.search(r"gamma\s*=\s*(\d+)", block)
            NIGHT["gamma"] = int(g.group(1)) if g else 100
        else:
            end = mins
    return start, end, temp

def night_now(now_min, start, end):
    return (start <= now_min or now_min < end) if start > end else (start <= now_min < end)

def last_boundary(now, start, end):
    """epoch of the most recent profile switch"""
    lt = time.localtime(now)
    midnight = now - (lt.tm_hour * 3600 + lt.tm_min * 60 + lt.tm_sec)
    cands = [midnight + m * 60 - d for m in (start, end) for d in (0, 86400)]
    return max(c for c in cands if c <= now)

def state():
    start, end, _ = schedule()
    now = time.time()
    try:
        st = os.stat(STATE)
        if st.st_mtime >= last_boundary(now, start, end):
            return open(STATE).read().strip() == "on"
    except OSError:
        pass
    lt = time.localtime(now)
    return night_now(lt.tm_hour * 60 + lt.tm_min, start, end)

def hs(*args):
    if not subprocess.run(["pgrep", "-x", "hyprsunset"], capture_output=True).stdout:
        subprocess.Popen(["hyprsunset"], start_new_session=True, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(0.5)
    if args:
        subprocess.run(["hyprctl", "hyprsunset", *map(str, args)], capture_output=True)

cmd = sys.argv[1] if len(sys.argv) > 1 else "toggle"
if cmd == "state":
    print("true" if state() else "false")
elif cmd == "on":
    t = schedule()[2]; hs("temperature", t); hs("gamma", NIGHT["gamma"]); open(STATE, "w").write("on")
elif cmd == "off":
    hs("identity"); hs("gamma", 100); open(STATE, "w").write("off")
elif cmd == "autostart":          # called from hyprland.lua: only run the schedule if it is enabled
    schedule()
    if NIGHT.get("enabled", True):
        hs()
elif cmd == "schedule-state":
    schedule(); print("true" if NIGHT.get("enabled", True) else "false")
elif cmd == "toggle":
    os.execv(sys.executable, [sys.executable, __file__, "off" if state() else "on"])
elif cmd == "reset":
    try: os.remove(STATE)
    except OSError: pass
