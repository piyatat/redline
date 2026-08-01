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

const payload = JSON.parse(fs.readFileSync(feedbackPath, 'utf8'));
const errors = [];

if (!payload.screen || !payload.region) {
  errors.push('screen and region are required');
}
if (!payload.comment || String(payload.comment).trim() === '') {
  errors.push('comment must not be empty');
}
if (!payload.compositePngBase64) {
  errors.push('compositePngBase64 is required');
}
if (Array.isArray(payload.pins)) {
  for (const pin of payload.pins) {
    if (!pin.component || !pin.pin) {
      errors.push(`invalid pin entry: ${JSON.stringify(pin)}`);
    }
  }
}

if (errors.length) {
  console.error('validate-feedback failed:\n - ' + errors.join('\n - '));
  process.exit(1);
}

console.log(`validate-feedback: ok (${payload.screen}/${payload.region})`);
