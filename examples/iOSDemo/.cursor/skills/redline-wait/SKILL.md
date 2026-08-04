---
name: redline-wait
description: >-
  Wait for the next Redline designer feedback via MCP tool redline_wait_for_feedback,
  then inspect the inbox item and apply UI/spec fixes in the project. Use when the user
  asks to wait for redline feedback, poll Redline, or process a designer markup from
  the Mac inbox while staying in Cursor desktop (desktop MCP plugins available).
---

# Redline — wait for feedback

## Prerequisites

- **Redline.app** is running (receiver on `:8765`).
- Settings → **When feedback arrives** = **Cursor desktop (MCP)** so Agent CLI is not auto-started.
- Redline MCP server `redline` is enabled (project `.cursor/mcp.json` or Cursor Settings → MCP).
- Designer will **Send** a redline from the iOS or Android app (or use Mac Inbox).

## Steps

1. Call MCP tool **`redline_wait_for_feedback`** with `timeoutSeconds`: `"300"` (default is 300).
   - Do **not** treat an already-present inbox item as new; the tool waits for a new id.
   - On success the Mac Inbox item is marked **Running** (`agent_running`).
2. When it returns, note `id`, `screen`, `region`, `comment`, `spec`, `runtime`, and `bundleDirectory`.
   - Composite PNG is omitted from MCP JSON (`compositeOmitted: true`) — read the image from disk.
   - `composite.png` already includes baked markup strokes (display as-is).
3. Optionally call **`redline_inbox_show`** with that `id` if you need details again.
4. Read staged feedback assets (preferred):
   - `.redline-feedback/prompt.md`
   - `.redline-feedback/composite.png`
   - fallback: absolute paths under `bundleDirectory`
5. Implement the designer request in this repo (use other MCP tools if needed).
6. Call **`redline_inbox_set_status`** with the same `id`:
   - `status`: `"applied"` when done (alias `"finished"`), or `"failed"` if blocked
   - `summary`: short note of what changed (shown in Redline Inbox)
7. Summarize what changed and which screen/region it addressed.

## Notes

- Prefer this desktop Agent path when desktop MCP plugins are required — headless CLI may not expose them.
- Always update inbox status when you finish (or fail) so designers see progress in Redline.app.
- If the MCP tool is missing, tell the user to run Redline.app → Settings → **Install into project** / **Open MCP install in Cursor**.
- Set `REDLINE_API_TOKEN` in the shell / Cursor MCP env if the Mac receiver requires a token — do not commit tokens into `.cursor/mcp.json`.
