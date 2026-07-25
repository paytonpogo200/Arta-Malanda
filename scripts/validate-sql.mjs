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

const sql = fs.readFileSync(sqlPath, 'utf8');
const definitions = new Map();
const definitionPattern = /create\s+or\s+replace\s+function\s+public\.([a-zA-Z0-9_]+)\s*\(([\s\S]*?)\)\s*(?:returns|language)\b/gi;
let definitionMatch;

while ((definitionMatch = definitionPattern.exec(sql))) {
  const [, name, params] = definitionMatch;
  const signatures = definitions.get(name) ?? new Set();
  signatures.add(normalizeSignature(params));
  definitions.set(name, signatures);
}

const duplicateOverloads = Array.from(definitions.entries())
  .filter(([, signatures]) => signatures.size > 1)
  .map(([name, signatures]) => `${name}: ${Array.from(signatures).join(' | ')}`);

const grants = new Set(
  Array.from(sql.matchAll(/grant\s+execute\s+on\s+function\s+public\.([a-zA-Z0-9_]+)\s*\(/gi))
    .map((match) => match[1])
);

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

if (duplicateOverloads.length) {
  failures.push(`Duplicate live SQL function overloads:\n${duplicateOverloads.map((entry) => `- ${entry}`).join('\n')}`);
}

if (missingDefinitions.length) {
  failures.push(`RPC calls without SQL definitions:\n${missingDefinitions.map((name) => `- ${name}`).join('\n')}`);
}

if (missingGrants.length) {
  failures.push(`RPC calls without execute grants:\n${missingGrants.map((name) => `- ${name}`).join('\n')}`);
}

if (failures.length) {
  console.error(failures.join('\n\n'));
  process.exit(1);
}

console.log(`SQL validation passed: ${definitions.size} functions, ${rpcCalls.size} app RPC calls checked.`);
