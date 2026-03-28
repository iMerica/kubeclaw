#!/usr/bin/env node
'use strict';

const fs = require('fs');

function tryParse(text) {
  try {
    return JSON.parse(text);
  } catch (_) {}

  let JSON5;
  try {
    JSON5 = require('json5');
  } catch (_) {
    try {
      JSON5 = require('/opt/kubeclaw/deps/node_modules/json5');
    } catch (err) {
      throw new Error(
        'Failed to parse input as strict JSON, and JSON5 parser is unavailable. ' +
          'Install json5 or provide valid JSON.'
      );
    }
  }

  return JSON5.parse(text);
}

function mergePatch(base, patch) {
  if (typeof patch !== 'object' || patch === null || Array.isArray(patch)) {
    return patch;
  }

  const result = Object.assign({}, base);
  for (const [key, value] of Object.entries(patch)) {
    if (value === null) {
      delete result[key];
    } else if (
      typeof value === 'object' &&
      !Array.isArray(value) &&
      typeof result[key] === 'object' &&
      result[key] !== null &&
      !Array.isArray(result[key])
    ) {
      result[key] = mergePatch(result[key], value);
    } else {
      result[key] = value;
    }
  }

  return result;
}

const [, , baseFile, patchFile] = process.argv;
if (!baseFile || !patchFile) {
  console.error('Usage: merge-json5.js <base-file> <patch-file>');
  process.exit(1);
}

const base = tryParse(fs.readFileSync(baseFile, 'utf8'));
const patch = tryParse(fs.readFileSync(patchFile, 'utf8'));

const merged = mergePatch(base, patch);
process.stdout.write(JSON.stringify(merged, null, 2) + '\n');
