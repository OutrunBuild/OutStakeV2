#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

function usage() {
  console.error('Usage: read-process-config.js policy <dot.path> [--lines]');
  process.exit(1);
}

const [, , kind, keyPath, format] = process.argv;

if (kind !== 'policy' || !keyPath) {
  usage();
}

const configPath = process.env.PROCESS_POLICY_FILE || 'docs/process/policy.json';
const absolutePath = path.resolve(configPath);
const document = JSON.parse(fs.readFileSync(absolutePath, 'utf8'));

let value = document;
for (const key of keyPath.split('.')) {
  if (key === '') continue;
  if (value == null || !(key in value)) {
    console.error(`Missing config key '${keyPath}' in ${configPath}`);
    process.exit(1);
  }
  value = value[key];
}

if (format === '--lines') {
  if (!Array.isArray(value)) {
    console.error(`Config key '${keyPath}' in ${configPath} is not an array`);
    process.exit(1);
  }

  for (const entry of value) {
    process.stdout.write(String(entry));
    process.stdout.write('\n');
  }
  process.exit(0);
}

if (typeof value === 'object') {
  process.stdout.write(JSON.stringify(value));
  process.exit(0);
}

process.stdout.write(String(value));
