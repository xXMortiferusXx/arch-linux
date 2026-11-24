#!/usr/bin/env python3
"""Beantwortet nur die Passwort-Prompts von install-arch."""
import os, re, sys, time
log_path, cmd_path = sys.argv[1], sys.argv[2]
steps = [("New password:", "test"), ("Retype new password:", "test"),
         ("New password:", "test"), ("Retype new password:", "test")]
pos = 0; buf = ""; idx = 0; deadline = time.time() + 1800
while time.time() < deadline:
    time.sleep(0.3)
    if os.path.exists(log_path):
        size = os.path.getsize(log_path)
        if size > pos:
            with open(log_path, "r", errors="replace") as f:
                f.seek(pos); buf += f.read().replace("\r", "")
            pos = size
    if "Installation fertig" in buf:
        print("FERTIG", flush=True); break
    while idx < len(steps) and steps[idx][0] in buf:
        pat, ans = steps[idx]
        buf = buf.split(pat, 1)[1]
        with open(cmd_path, "a") as c: c.write(ans + "\n")
        print(f"[{time.strftime('%H:%M:%S')}] -> {ans!r} ({pat})", flush=True)
        idx += 1
        time.sleep(0.8)
