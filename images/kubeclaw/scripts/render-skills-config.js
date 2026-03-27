#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const skillsDir = process.argv[2];
const outputPath = process.argv[3];

if (!skillsDir || !outputPath) {
  console.error('Usage: render-skills-config.js <skills-dir> <output-file>');
  process.exit(1);
}

const boolFromEnv = (name, fallback) => {
  const raw = process.env[name];
  if (raw === undefined || raw === '') return fallback;
  return String(raw).toLowerCase() === 'true';
};

const watch = boolFromEnv('KUBECLAW_SKILLS_WATCH', true);
const nodeManager = process.env.KUBECLAW_SKILLS_NODE_MANAGER || 'npm';
let extraDirs = [];

try {
  extraDirs = JSON.parse(process.env.KUBECLAW_SKILLS_EXTRA_DIRS_JSON || '[]');
  if (!Array.isArray(extraDirs)) extraDirs = [];
} catch (_) {
  extraDirs = [];
}

const entries = {};
if (fs.existsSync(skillsDir)) {
  for (const dirent of fs.readdirSync(skillsDir, { withFileTypes: true })) {
    if (!dirent.isDirectory()) continue;
    const skillName = dirent.name;
    const skillFile = path.join(skillsDir, skillName, 'SKILL.md');
    if (fs.existsSync(skillFile)) {
      entries[skillName] = { enabled: true };
    }
  }
}

const payload = {
  skills: {
    load: {
      watch,
      extraDirs
    },
    install: {
      nodeManager
    },
    entries
  }
};

fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, JSON.stringify(payload, null, 2) + '\n');
