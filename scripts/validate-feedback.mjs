#!/usr/bin/env node
/**
 * Validate a Redline feedback bundle (feedback.json) when REDLINE_BUNDLE_DIR is set.
 */
import fs from 'node:fs';
import path from 'node:path';

const bundleDir = process.env.REDLINE_BUNDLE_DIR;
if (!bundleDir) {
  console.log('validate-feedback: skipped (no REDLINE_BUNDLE_DIR)');
  process.exit(0);
}

const feedbackPath = path.join(bundleDir, 'feedback.json');
if (!fs.existsSync(feedbackPath)) {
  console.error('validate-feedback: missing feedback.json');
  process.exit(1);
}

let payload;
try {
  payload = JSON.parse(fs.readFileSync(feedbackPath, 'utf8'));
} catch (err) {
  console.error(`validate-feedback: invalid JSON (${err.message})`);
  process.exit(1);
}

const errors = [];

if (payload.schema !== 1 && payload.schema !== undefined) {
  errors.push(`unsupported schema version: ${payload.schema}`);
}
if (!payload.screen || !payload.region) {
  errors.push('screen and region are required');
}
if (!payload.platform) {
  errors.push('platform is required');
}
if (!payload.capturedTs) {
  errors.push('capturedTs is required');
}
if (!payload.comment || String(payload.comment).trim() === '') {
  errors.push('comment must not be empty');
}
if (!payload.compositePngBase64) {
  errors.push('compositePngBase64 is required');
} else if (typeof payload.compositePngBase64 !== 'string' || payload.compositePngBase64.length < 8) {
  errors.push('compositePngBase64 looks empty or truncated');
}
if (payload.pins !== undefined && !Array.isArray(payload.pins)) {
  errors.push('pins must be an array when present');
}
if (Array.isArray(payload.pins)) {
  for (const pin of payload.pins) {
    if (!pin || !pin.component || !pin.pin) {
      errors.push(`invalid pin entry: ${JSON.stringify(pin)}`);
    }
  }
}
if (payload.strokes !== undefined && !Array.isArray(payload.strokes)) {
  errors.push('strokes must be an array when present');
}

if (errors.length) {
  console.error('validate-feedback failed:\n - ' + errors.join('\n - '));
  process.exit(1);
}

console.log(`validate-feedback: ok (${payload.screen}/${payload.region})`);
