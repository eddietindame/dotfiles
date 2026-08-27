#!/usr/bin/env python3
"""Keep herdr's agent panel scoped to the focused space.

agent.view.set accepts a {"context": "current_workspace_id"} filter value, but
that resolves against the calling client — an API connection is not one, so the
view goes active while matching nothing. Instead we subscribe to
workspace.focused and re-apply a literal workspace_id filter on every change.

Started and stopped by herdr-agent-view.sh; not meant to be run by hand.

Usage: herdr-agent-view-follow.py <socket-path> <source-id>
"""

import json
import socket
import sys
import time


def connect(sock_path):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(sock_path)
    return s


def call(sock_path, source, method, params):
    """One-shot request on its own connection."""
    s = connect(sock_path)
    try:
        s.sendall((json.dumps({"id": f"{source}:{method}", "method": method, "params": params}) + "\n").encode())
        s.settimeout(5)
        buf = b""
        while b"\n" not in buf:
            chunk = s.recv(65536)
            if not chunk:
                break
            buf += chunk
        return json.loads(buf.split(b"\n")[0]) if buf else {}
    finally:
        s.close()


def spaces(sock_path, source):
    return call(sock_path, source, "workspace.list", {}).get("result", {}).get("workspaces", [])


def apply_filter(sock_path, source, workspace_id, label):
    call(sock_path, source, "agent.view.set", {
        "source": source,
        "label": label or workspace_id,
        "filter": {"op": "eq", "field": "workspace_id", "value": workspace_id},
    })
    log(f"scoped to {label or workspace_id} ({workspace_id})")


def log(message):
    print(f"{time.strftime('%H:%M:%S')} follow: {message}", flush=True)


def label_for(sock_path, source, workspace_id):
    for w in spaces(sock_path, source):
        if w["workspace_id"] == workspace_id:
            return w.get("label")
    return None


def run(sock_path, source, interval=0.4):
    """Poll for the focused space and re-scope when it changes.

    The workspace.focused *event* looked like the right trigger, but herdr
    emits it continuously for every space rather than on change — measured at
    ~10/second alternating between two spaces while nothing was happening — so
    subscribing to it makes the panel flicker. workspace.list reports focus
    authoritatively, and polling it is cheap over a local socket.
    """
    current = None
    while True:
        focused = next((w for w in spaces(sock_path, source) if w.get("focused")), None)
        if focused is not None and focused["workspace_id"] != current:
            current = focused["workspace_id"]
            apply_filter(sock_path, source, current, focused.get("label"))
        time.sleep(interval)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    try:
        run(sys.argv[1], sys.argv[2])
    except (BrokenPipeError, ConnectionResetError, ConnectionRefusedError,
            FileNotFoundError, OSError) as exc:
        log(f"exiting: {exc}")
