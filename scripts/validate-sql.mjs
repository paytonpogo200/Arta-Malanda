import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, '..');
const sqlPath = path.join(repoRoot, 'supabase', 'RUN_THIS_IN_SUPABASE.sql');
const srcRoot = path.join(repoRoot, 'src');

function walkFiles(directory, files = []) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const fullPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      walkFiles(fullPath, files);
    } else if (/\.(ts|tsx)$/.test(entry.name)) {
      files.push(fullPath);
    }
  }
  return files;
}

function normalizeSignature(rawParams) {
  return rawParams
    .split(',')
    .map((param) => param.trim().replace(/\s+/g, ' '))
    .filter(Boolean)
    .join(', ');
}

function lineNumberAt(source, index) {
  return source.slice(0, index).split(/\r?\n/).length;
}

const sql = fs.readFileSync(sqlPath, 'utf8');
const definitions = new Map();
const firstDefinitionLines = new Map();
const definitionPattern = /create\s+or\s+replace\s+function\s+public\.([a-zA-Z0-9_]+)\s*\(([\s\S]*?)\)\s*(?:returns|language)\b/gi;
let definitionMatch;

while ((definitionMatch = definitionPattern.exec(sql))) {
  const [, name, params] = definitionMatch;
  const signatures = definitions.get(name) ?? new Set();
  signatures.add(normalizeSignature(params));
  definitions.set(name, signatures);
  if (!firstDefinitionLines.has(name)) {
    firstDefinitionLines.set(name, lineNumberAt(sql, definitionMatch.index));
  }
}

const duplicateOverloads = Array.from(definitions.entries())
  .filter(([, signatures]) => signatures.size > 1)
  .map(([name, signatures]) => `${name}: ${Array.from(signatures).join(' | ')}`);

const grants = new Set(
  Array.from(sql.matchAll(/grant\s+execute\s+on\s+function\s+public\.([a-zA-Z0-9_]+)\s*\(/gi))
    .map((match) => match[1])
);

const grantOrderProblems = [];
const grantsWithoutDefinitions = [];
for (const match of sql.matchAll(/grant\s+execute\s+on\s+function\s+public\.([a-zA-Z0-9_]+)\s*\(/gi)) {
  const name = match[1];
  const grantLine = lineNumberAt(sql, match.index);
  const definitionLine = firstDefinitionLines.get(name);
  if (!definitionLine) {
    grantsWithoutDefinitions.push(`${name} at line ${grantLine}`);
  } else if (definitionLine > grantLine) {
    grantOrderProblems.push(`${name}: grant at line ${grantLine}, definition at line ${definitionLine}`);
  }
}

const rpcCalls = new Set();
for (const filePath of walkFiles(srcRoot)) {
  const source = fs.readFileSync(filePath, 'utf8');
  for (const match of source.matchAll(/supabase\.rpc\(['"]([^'"]+)['"]/g)) {
    rpcCalls.add(match[1]);
  }
}

const missingDefinitions = Array.from(rpcCalls).filter((name) => !definitions.has(name)).sort();
const missingGrants = Array.from(rpcCalls).filter((name) => !grants.has(name)).sort();
const failures = [];
const destructiveSeedPatterns = [
  {
    label: 'market product seed conflict updates can reset DM-edited shop names, sections, prices, or stock',
    pattern: /on\s+conflict\s*\(\s*product_key\s*\)\s+do\s+update/gi
  },
  {
    label: 'city seed conflict updates can revert DM-edited city names, colors, descriptions, or order',
    pattern: /on\s+conflict\s*\(\s*city_key\s*\)\s+do\s+update/gi
  },
  {
    label: 'Calostrynn vendor pruning can delete DM-created shops',
    pattern: /delete\s+from\s+public\.shop_vendors\s+where\s+city_key\s*=\s*'calostrynn'/gi
  },
  {
    label: 'vendor-owned product pruning can delete DM-created shop products',
    pattern: /delete\s+from\s+public\.market_products\s+p\s+using\s+[a-zA-Z0-9_]+_vendor/gi
  },
  {
    label: 'current residence seed reset can undo the DM-selected residence city',
    pattern: /set\s+is_current_residence\s*=\s*city_key\s*=/gi
  },
  {
    label: 'hardcoded City Market reset can undo DM-edited shop display settings',
    pattern: /set\s+name\s*=\s*'City Market'/gi
  }
];

const destructiveSeedProblems = [];
for (const { label, pattern } of destructiveSeedPatterns) {
  for (const match of sql.matchAll(pattern)) {
    destructiveSeedProblems.push(`${label} at line ${lineNumberAt(sql, match.index)}`);
  }
}

if (duplicateOverloads.length) {
  failures.push(`Duplicate live SQL function overloads:\n${duplicateOverloads.map((entry) => `- ${entry}`).join('\n')}`);
}

if (missingDefinitions.length) {
  failures.push(`RPC calls without SQL definitions:\n${missingDefinitions.map((name) => `- ${name}`).join('\n')}`);
}

if (missingGrants.length) {
  failures.push(`RPC calls without execute grants:\n${missingGrants.map((name) => `- ${name}`).join('\n')}`);
}

if (grantsWithoutDefinitions.length) {
  failures.push(`Execute grants without SQL definitions:\n${grantsWithoutDefinitions.map((entry) => `- ${entry}`).join('\n')}`);
}

if (grantOrderProblems.length) {
  failures.push(`Execute grants before SQL definitions:\n${grantOrderProblems.map((entry) => `- ${entry}`).join('\n')}`);
}

if (destructiveSeedProblems.length) {
  failures.push(`City/shop seed reset patterns found:\n${destructiveSeedProblems.map((entry) => `- ${entry}`).join('\n')}`);
}

if (failures.length) {
  console.error(failures.join('\n\n'));
  process.exit(1);
}

console.log(`SQL validation passed: ${definitions.size} functions, ${rpcCalls.size} app RPC calls checked.`);
