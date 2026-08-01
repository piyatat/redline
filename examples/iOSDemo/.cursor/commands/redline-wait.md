---
description: Wait for the next Redline designer feedback (MCP redline_wait_for_feedback), then fix the UI/spec.
---

Wait for new Redline designer feedback and act on it.

Prerequisites: Redline.app running; Settings → When feedback arrives = **Cursor desktop (MCP)**.

1. Ensure the `redline` MCP server is available.
2. Call **`redline_wait_for_feedback`** with `timeoutSeconds` = `300`.
3. When feedback arrives, read `.redline-feedback/prompt.md` and `.redline-feedback/composite.png` (PNG is not in the MCP JSON).
4. Apply the requested change in this project. Use other MCP tools if needed.
5. Call **`redline_inbox_set_status`** with `id` from step 2, `status` = `applied` (or `failed`), and a short `summary`.
6. Report what you changed.

If `redline_wait_for_feedback` is unavailable, tell me to install Redline MCP from Redline.app Settings or `.cursor/mcp.json`.
