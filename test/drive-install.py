#!/usr/bin/env python3
"""Treibt install-arch ueber die serielle Konsole (QEMU -serial socket).

Antwortet in fester Reihenfolge. Der Puffer wird nach jeder Antwort erneut
geprueft, damit mehrere Prompts im selben Log-Stueck nicht verloren gehen.
"""
import os
import re
import sys
import time

log_path, cmd_path = sys.argv[1], sys.argv[2]
host_choice = sys.argv[3] if len(sys.argv) > 3 else "1"

steps = [
    (r"Auswahl \[", host_choice),  # Host (nur ohne --host)
    (r"Auswahl \[", "1"),        # Ziel-Datentraeger
    (r"Auswahl \[0-", "1"),      # Spiele-Platte
    (r"Fortfahren\?", "j"),
    (r"New password:", "test"),  # root
    (r"Retype new password:", "test"),
    (r"New password:", "test"),  # User
    (r"Retype new password:", "test"),
]

pos = 0
buf = ""
idx = 0
deadline = time.time() + 3600
done = False

while time.time() < deadline:
    time.sleep(0.3)
    if os.path.exists(log_path):
        size = os.path.getsize(log_path)
        if size > pos:
            with open(log_path, "r", errors="replace") as f:
                f.seek(pos)
                buf += f.read().replace("\r", "")
            pos = size

    if "Installation fertig" in buf:
        done = True
        break

    matched = True
    while matched and idx < len(steps):
        matched = False
        pattern, answer = steps[idx]
        m = re.search(pattern, buf)
        if m:
            buf = buf[m.end():]
            with open(cmd_path, "a") as c:
                c.write(answer + "\n")
            print(f"[{time.strftime('%H:%M:%S')}] -> {answer!r}  ({pattern})", flush=True)
            idx += 1
            matched = True
            time.sleep(0.6)

print("FERTIG" if done else "ABBRUCH/TIMEOUT", flush=True)
