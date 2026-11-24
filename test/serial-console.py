#!/usr/bin/env python3
"""Mini-Konsole fuer QEMU -serial (Unix-Socket).

Liest die serielle Ausgabe in eine Logdatei und schickt Zeilen aus einer
Kommando-Datei an die Gast-Konsole (jede Zeile + Enter).

  serial-console.py <socket> <log> <cmd-file>
"""
import os
import socket
import sys
import threading
import time

sock_path, log_path, cmd_path = sys.argv[1:4]

s = socket.socket(socket.AF_UNIX)
while True:
    try:
        s.connect(sock_path)
        break
    except (FileNotFoundError, ConnectionRefusedError):
        time.sleep(0.2)

log = open(log_path, "ab", buffering=0)


def reader():
    while True:
        try:
            data = s.recv(4096)
        except OSError:
            break
        if not data:
            break
        log.write(data)


threading.Thread(target=reader, daemon=True).start()

open(cmd_path, "a").close()
pos = os.path.getsize(cmd_path)

while True:
    time.sleep(0.15)
    size = os.path.getsize(cmd_path)
    if size <= pos:
        continue
    with open(cmd_path, "r", errors="replace") as f:
        f.seek(pos)
        chunk = f.read()
    pos = size
    for line in chunk.splitlines():
        s.sendall((line + "\r").encode())
