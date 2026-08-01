#!/usr/bin/env bash
# Run Redline validation gates for a feedback bundle.
# Usage: run-gates.sh [workspace-root] [bundle-directory]
set -euo pipefail

WORKSPACE="${1:-$(pwd)}"
BUNDLE="${2:-}"

export REDLINE_WORKSPACE_ROOT="$WORKSPACE"
if [[ -n "$BUNDLE" ]]; then
  export REDLINE_BUNDLE_DIR="$BUNDLE"
fi

MANIFEST="${REDLINE_GATE_MANIFEST:-$WORKSPACE/scripts/gate-manifest.json}"
if [[ ! -f "$MANIFEST" ]]; then
  echo "No gate-manifest.json at $MANIFEST" >&2
  exit 1
fi

node -e "
const fs = require('fs');
const { execSync } = require('child_process');
const manifest = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
let failed = false;
for (const stage of manifest.stages) {
  const script = stage.script.startsWith('/')
    ? stage.script
    : require('path').join(process.argv[2], stage.script);
  if (!fs.existsSync(script)) {
    const msg = stage.required ? 'MISSING (required)' : 'skipped (optional)';
    console.log(\`[\${stage.name}] \${msg}: \${stage.script}\`);
    if (stage.required) failed = true;
    continue;
  }
  try {
    const args = (stage.args || []).join(' ');
    execSync(\`node \"\${script}\" \${args}\`, {
      cwd: process.argv[2],
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
" "$MANIFEST" "$WORKSPACE"
