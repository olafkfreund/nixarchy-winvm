#!/usr/bin/env python3
import json
import socket
import sys
import time


def main():
    socket_path, *args = sys.argv[1:]
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.connect(socket_path)
        sock.recv(4096)
        sock.sendall(b'{"execute":"qmp_capabilities"}\n')
        sock.recv(4096)
        def hmp(command_line):
            command = {
                "execute": "human-monitor-command",
                "arguments": {"command-line": command_line},
            }
            sock.sendall((json.dumps(command) + "\n").encode())
            sock.recv(4096)

        if args[:1] == ["screendump"]:
            path = args[1] if len(args) > 1 else "/tmp/nixarchy-try.ppm"
            command = {"execute": "screendump", "arguments": {"filename": path}}
        elif args[:1] == ["type"] and len(args) == 2:
            for char in args[1]:
                lower = char.lower()
                if lower.isalnum() or lower in "-_. /,=:#*';":
                    key = {" ": "spc", "/": "slash", ".": "dot", ",": "comma", "=": "equal", ":": "shift-semicolon", "#": "shift-3", "-": "minus", "_": "shift-minus", "*": "shift-8", "'": "apostrophe", ";": "semicolon"}.get(lower, lower)
                    hmp(f"sendkey {'shift-' if char.isupper() else ''}{key}")
                    time.sleep(0.03)
                else:
                    raise SystemExit(f"unsupported character: {char!r}")
            return
        elif args[:1] == ["key"] and len(args) == 2:
            command = {
                "execute": "human-monitor-command",
                "arguments": {"command-line": f"sendkey {args[1]}"},
            }
        else:
            raise SystemExit("usage: vm-qmp screendump [path] | vm-qmp key <qcode[,qcode...]> | vm-qmp type <text>")
        sock.sendall((json.dumps(command) + "\n").encode())
        print(sock.recv(4096).decode().strip())


if __name__ == "__main__":
    main()
