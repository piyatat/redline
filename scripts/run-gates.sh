#!/usr/bin/env bash
# Run Redline validation gates for a feedback bundle.
# Usage: run-gates.sh [workspace-root] [bundle-directory]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE="${1:-$REPO_ROOT}"
BUNDLE="${2:-}"

export REDLINE_WORKSPACE_ROOT="$WORKSPACE"
if [[ -n "$BUNDLE" ]]; then
  export REDLINE_BUNDLE_DIR="$BUNDLE"
fi

MANIFEST="${REDLINE_GATE_MANIFEST:-$WORKSPACE/scripts/gate-manifest.json}"
SCRIPT_BASE="$WORKSPACE"
if [[ ! -f "$MANIFEST" ]]; then
  if [[ -f "$REPO_ROOT/scripts/gate-manifest.json" ]]; then
    MANIFEST="$REPO_ROOT/scripts/gate-manifest.json"
    SCRIPT_BASE="$REPO_ROOT"
  else
    echo "No gate-manifest.json at $MANIFEST" >&2
    exit 1
  fi
fi

node -e "
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const manifest = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
const scriptBase = process.argv[2];
const cwd = process.argv[3];
let failed = false;
for (const stage of manifest.stages) {
  const script = stage.script.startsWith('/')
    ? stage.script
    : path.join(scriptBase, stage.script);
  const resolved = path.resolve(script);
  const baseResolved = path.resolve(scriptBase) + path.sep;
  if (!resolved.startsWith(baseResolved) && resolved !== path.resolve(scriptBase)) {
    console.error(\`[\${stage.name}] blocked script outside base: \${stage.script}\`);
    if (stage.required) failed = true;
    continue;
  }
  if (!fs.existsSync(resolved)) {
    const msg = stage.required ? 'MISSING (required)' : 'skipped (optional)';
    console.log(\`[\${stage.name}] \${msg}: \${stage.script}\`);
    if (stage.required) failed = true;
    continue;
  }
  try {
    const args = Array.isArray(stage.args) ? stage.args.map(String) : [];
    execFileSync(process.execPath, [resolved, ...args], {
      cwd,
      stdio: 'inherit',
      env: { ...process.env, REDLINE_BUNDLE_DIR: process.env.REDLINE_BUNDLE_DIR || '' },
    });
    console.log(\`[\${stage.name}] pass\`);
  } catch {
    console.error(\`[\${stage.name}] FAIL\`);
    if (stage.required) failed = true;
  }
}
process.exit(failed ? 1 : 0);
" "$MANIFEST" "$SCRIPT_BASE" "$WORKSPACE"
