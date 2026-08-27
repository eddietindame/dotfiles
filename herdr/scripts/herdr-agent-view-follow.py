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


def run(sock_path, source):
    # Catch up with wherever focus is right now before waiting for changes.
    current = None
    focused = next((w for w in spaces(sock_path, source) if w.get("focused")), None)
    if focused:
        apply_filter(sock_path, source, focused["workspace_id"], focused.get("label"))
        current = focused["workspace_id"]

    s = connect(sock_path)
    s.sendall((json.dumps({
        "id": f"{source}:subscribe",
        "method": "events.subscribe",
        "params": {"subscriptions": [{"type": "workspace.focused"}]},
    }) + "\n").encode())

    log("subscribed to workspace.focused")
    buf = b""
    while True:
        chunk = s.recv(65536)
        if not chunk:
            log("server closed the connection")
            return
        buf += chunk
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            if not line.strip():
                continue
            try:
                msg = json.loads(line)
            except json.JSONDecodeError:
                continue
            # Envelope is {"event": "<name>", "data": {...}} — "event" is a
            # string, so the payload has to come from "data".
            data = msg.get("data")
            if not isinstance(data, dict) or data.get("type") != "workspace_focused":
                continue
            wid = data["workspace_id"]
            # herdr re-emits workspace_focused constantly, not just on change,
            # so only act when the focused space actually differs.
            if wid == current:
                continue
            current = wid
            apply_filter(sock_path, source, wid, label_for(sock_path, source, wid))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    try:
        run(sys.argv[1], sys.argv[2])
    except (BrokenPipeError, ConnectionResetError, FileNotFoundError) as exc:
        log(f"exiting: {exc}")
