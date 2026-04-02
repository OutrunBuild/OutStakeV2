#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

function usage() {
  console.log(`Usage: check-coverage.js [--lcov-file <path>] [--policy-file <path>]

Options:
  --lcov-file <path>    Read an existing LCOV file instead of relying on the default path
  --policy-file <path>  Read coverage policy from a custom JSON file
  --help                Show this help message`);
}

function parseArgs(argv) {
  const options = {
    lcovFile: process.env.COVERAGE_LCOV_FILE || '',
    policyFile: process.env.PROCESS_POLICY_FILE || 'docs/process/policy.json',
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--help') {
      options.help = true;
      continue;
    }
    if (arg === '--lcov-file') {
      if (i + 1 >= argv.length) {
        throw new Error('missing value for --lcov-file');
      }
      options.lcovFile = argv[i + 1];
      i += 1;
      continue;
    }
    if (arg === '--policy-file') {
      if (i + 1 >= argv.length) {
        throw new Error('missing value for --policy-file');
      }
      options.policyFile = argv[i + 1];
      i += 1;
      continue;
    }
    throw new Error(`unknown argument: ${arg}`);
  }

  return options;
}

function loadJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function createMetric(found = 0, hit = 0) {
  return { found, hit };
}

function addMetric(target, source) {
  target.found += source.found;
  target.hit += source.hit;
}

function createBucket(group) {
  return {
    name: group.name,
    prefix: group.prefix || '',
    thresholds: {
      line: group.lineThreshold,
      function: group.functionThreshold,
      branch: group.branchThreshold,
    },
    files: [],
    metrics: {
      line: createMetric(),
      function: createMetric(),
      branch: createMetric(),
    },
  };
}

function safeParseInt(value) {
  const parsed = Number.parseInt(value, 10);
  return Number.isNaN(parsed) ? 0 : parsed;
}

function parseRecord(block) {
  const record = {
    file: '',
    metrics: {
      line: createMetric(),
      function: createMetric(),
      branch: createMetric(),
    },
  };

  const fallback = {
    daFound: 0,
    daHit: 0,
    fnFound: 0,
    fnHit: 0,
    fnSeen: new Set(),
    brFound: 0,
    brHit: 0,
  };

  for (const line of block.split('\n')) {
    if (!line) continue;

    if (line.startsWith('SF:')) {
      record.file = line.slice(3).trim();
      continue;
    }

    if (line.startsWith('LF:')) {
      record.metrics.line.found = safeParseInt(line.slice(3));
      continue;
    }

    if (line.startsWith('LH:')) {
      record.metrics.line.hit = safeParseInt(line.slice(3));
      continue;
    }

    if (line.startsWith('FNF:')) {
      record.metrics.function.found = safeParseInt(line.slice(4));
      continue;
    }

    if (line.startsWith('FNH:')) {
      record.metrics.function.hit = safeParseInt(line.slice(4));
      continue;
    }

    if (line.startsWith('BRF:')) {
      record.metrics.branch.found = safeParseInt(line.slice(4));
      continue;
    }

    if (line.startsWith('BRH:')) {
      record.metrics.branch.hit = safeParseInt(line.slice(4));
      continue;
    }

    if (line.startsWith('DA:')) {
      const [, hitCount] = line.slice(3).split(',');
      fallback.daFound += 1;
      if (safeParseInt(hitCount) > 0) {
        fallback.daHit += 1;
      }
      continue;
    }

    if (line.startsWith('FN:')) {
      fallback.fnFound += 1;
      continue;
    }

    if (line.startsWith('FNDA:')) {
      const payload = line.slice(5);
      const commaIndex = payload.indexOf(',');
      const hits = commaIndex === -1 ? payload : payload.slice(0, commaIndex);
      const name = commaIndex === -1 ? payload : payload.slice(commaIndex + 1);
      if (safeParseInt(hits) > 0 && !fallback.fnSeen.has(name)) {
        fallback.fnHit += 1;
        fallback.fnSeen.add(name);
      }
      continue;
    }

    if (line.startsWith('BRDA:')) {
      const parts = line.slice(5).split(',');
      const taken = parts[3] || '-';
      fallback.brFound += 1;
      if (taken !== '-' && safeParseInt(taken) > 0) {
        fallback.brHit += 1;
      }
    }
  }

  if (record.metrics.line.found === 0 && fallback.daFound > 0) {
    record.metrics.line = createMetric(fallback.daFound, fallback.daHit);
  }
  if (record.metrics.function.found === 0 && fallback.fnFound > 0) {
    record.metrics.function = createMetric(fallback.fnFound, fallback.fnHit);
  }
  if (record.metrics.branch.found === 0 && fallback.brFound > 0) {
    record.metrics.branch = createMetric(fallback.brFound, fallback.brHit);
  }

  return record;
}

function formatPercent(metric) {
  if (metric.found === 0) {
    return 'N/A';
  }
  return `${((metric.hit / metric.found) * 100).toFixed(2)}%`;
}

function evaluateMetric(metric, threshold) {
  if (threshold === 0) {
    return {
      pass: true,
      summary: `${formatPercent(metric)} (${metric.hit}/${metric.found})`,
      detail: 'threshold=0',
    };
  }

  if (metric.found === 0) {
    return {
      pass: true,
      summary: `N/A (${metric.hit}/${metric.found})`,
      detail: `threshold=${threshold}% no measurable items`,
    };
  }

  const percent = (metric.hit / metric.found) * 100;
  return {
    pass: percent >= threshold,
    summary: `${percent.toFixed(2)}% (${metric.hit}/${metric.found})`,
    detail: `threshold=${threshold}%`,
  };
}

function main() {
  let options;
  try {
    options = parseArgs(process.argv.slice(2));
  } catch (error) {
    console.error(`[check-coverage] ERROR: ${error.message}`);
    usage();
    process.exit(1);
  }

  if (options.help) {
    usage();
    process.exit(0);
  }

  const policyPath = path.resolve(options.policyFile);
  const policy = loadJson(policyPath);
  const coveragePolicy = policy.coverage;
  if (!coveragePolicy) {
    console.error(`[check-coverage] ERROR: missing coverage policy in ${policyPath}`);
    process.exit(1);
  }

  const lcovFile = path.resolve(options.lcovFile || coveragePolicy.default_lcov_path);
  if (!fs.existsSync(lcovFile)) {
    console.error(`[check-coverage] ERROR: LCOV file not found: ${lcovFile}`);
    process.exit(1);
  }

  const includePattern = new RegExp(coveragePolicy.include_pattern);
  const groups = coveragePolicy.groups.map((group) => ({
    name: group.name,
    prefix: group.prefix,
    lineThreshold: coveragePolicy.line_threshold,
    functionThreshold: coveragePolicy.function_threshold,
    branchThreshold: group.branch_threshold,
  }));
  groups.sort((left, right) => right.prefix.length - left.prefix.length);

  const fallbackGroup = {
    name: coveragePolicy.fallback_group.name,
    prefix: '',
    lineThreshold: coveragePolicy.line_threshold,
    functionThreshold: coveragePolicy.function_threshold,
    branchThreshold: coveragePolicy.fallback_group.branch_threshold,
  };

  const bucketMap = new Map();
  for (const group of groups) {
    bucketMap.set(group.name, createBucket(group));
  }
  bucketMap.set(fallbackGroup.name, createBucket(fallbackGroup));

  const content = fs.readFileSync(lcovFile, 'utf8');
  const blocks = content.split('end_of_record');

  let includedFiles = 0;
  for (const block of blocks) {
    const trimmed = block.trim();
    if (!trimmed) continue;

    const record = parseRecord(trimmed);
    if (!record.file || !includePattern.test(record.file)) {
      continue;
    }

    includedFiles += 1;
    const group = groups.find((candidate) => record.file.startsWith(candidate.prefix)) || fallbackGroup;
    const bucket = bucketMap.get(group.name);
    bucket.files.push(record.file);
    addMetric(bucket.metrics.line, record.metrics.line);
    addMetric(bucket.metrics.function, record.metrics.function);
    addMetric(bucket.metrics.branch, record.metrics.branch);
  }

  if (includedFiles === 0) {
    console.error(`[check-coverage] ERROR: no source files matched ${coveragePolicy.include_pattern} in ${lcovFile}`);
    process.exit(1);
  }

  console.log(`[check-coverage] INFO: lcov=${lcovFile}`);
  console.log(`[check-coverage] INFO: included-files=${includedFiles}`);

  let hasFailure = false;
  for (const bucket of bucketMap.values()) {
    if (bucket.files.length === 0) {
      console.log(`[check-coverage] INFO: group=${bucket.name} skipped (no matching files)`);
      continue;
    }

    const lineResult = evaluateMetric(bucket.metrics.line, bucket.thresholds.line);
    const functionResult = evaluateMetric(bucket.metrics.function, bucket.thresholds.function);
    const branchResult = evaluateMetric(bucket.metrics.branch, bucket.thresholds.branch);
    const pass = lineResult.pass && functionResult.pass && branchResult.pass;
    if (!pass) {
      hasFailure = true;
    }

    console.log(`[check-coverage] ${pass ? 'PASS' : 'FAIL'}: group=${bucket.name} files=${bucket.files.length}`);
    console.log(`[check-coverage] INFO:   line=${lineResult.summary} ${lineResult.detail}`);
    console.log(`[check-coverage] INFO:   function=${functionResult.summary} ${functionResult.detail}`);
    console.log(`[check-coverage] INFO:   branch=${branchResult.summary} ${branchResult.detail}`);
  }

  if (hasFailure) {
    process.exit(1);
  }
}

main();
