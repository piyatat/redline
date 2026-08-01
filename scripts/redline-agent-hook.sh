#!/usr/bin/env bash
# Example agent hook — invoked by Redline.app AgentRunner:
#   redline-agent-hook.sh <inbox-item-id> <bundle-directory>
set -euo pipefail

ITEM_ID="${1:?item id}"
BUNDLE_DIR="${2:?bundle dir}"

echo "[redline-agent-hook] item=$ITEM_ID"
echo "[redline-agent-hook] bundle=$BUNDLE_DIR"

if [[ -f "$BUNDLE_DIR/prompt.md" ]]; then
  echo "[redline-agent-hook] --- prompt.md (head) ---"
  head -n 40 "$BUNDLE_DIR/prompt.md"
  echo "[redline-agent-hook] --- end ---"
  open "$BUNDLE_DIR/prompt.md" 2>/dev/null || true
else
  echo "[redline-agent-hook] warning: prompt.md missing"
  open "$BUNDLE_DIR" 2>/dev/null || true
fi

/usr/bin/osascript -e "display notification \"Feedback $ITEM_ID ready\" with title \"Redline agent hook\"" 2>/dev/null || true
exit 0
