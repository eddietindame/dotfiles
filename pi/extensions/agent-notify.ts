// Ring tmux/scripts/agent-notify.sh when Pi finishes, as the Claude Code and
// Codex hooks do. agent_settled, not agent_end: Pi may still retry, compact or
// pick up a queued message after agent_end. Pi has no permission prompts, so
// there is no "input" bell.
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { spawn } from "node:child_process";
import { homedir } from "node:os";

const script = `${homedir()}/.config/tmux/scripts/agent-notify.sh`;

export default function (pi: ExtensionAPI) {
  pi.on("agent_settled", async () => {
    spawn("bash", [script, "done"], { stdio: "ignore", detached: true }).unref();
  });
}
