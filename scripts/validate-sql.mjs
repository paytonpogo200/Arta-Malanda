import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, '..');
const sqlPaths = [
  path.join(repoRoot, 'supabase', 'RUN_THIS_IN_SUPABASE_PART_1.sql'),
  path.join(repoRoot, 'supabase', 'RUN_THIS_IN_SUPABASE_PART_2.sql')
];
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
    .map((param) => {
      let normalized = param.trim().replace(/\s+/g, ' ');
      normalized = normalized.replace(/\s+default\s+[\s\S]*$/i, '');
      normalized = normalized.replace(/\s*=\s*[\s\S]*$/i, '');
      normalized = normalized.replace(/^(?:inout|in|out|variadic)\s+/i, '');
      const parts = normalized.split(' ');
      if (parts.length > 1 && /^[a-z_][a-z0-9_]*$/i.test(parts[0])) parts.shift();
      return parts.join(' ')
        .replace(/\bint\b/gi, 'integer')
        .replace(/\bdecimal\b/gi, 'numeric')
        .toLowerCase();
    })
    .filter(Boolean)
    .join(', ');
}

function lineNumberAt(source, index) {
  return source.slice(0, index).split(/\r?\n/).length;
}

const sql = sqlPaths.map((sqlPath) => fs.readFileSync(sqlPath, 'utf8')).join('\n');
const createdPublicTables = new Set(
  Array.from(sql.matchAll(/create\s+table\s+(?:if\s+not\s+exists\s+)?public\.([a-zA-Z0-9_]+)/gi))
    .map((match) => match[1])
);
const rlsEnabledPublicTables = new Set(
  Array.from(sql.matchAll(/alter\s+table\s+public\.([a-zA-Z0-9_]+)\s+enable\s+row\s+level\s+security/gi))
    .map((match) => match[1])
);
const definitions = new Map();
const firstDefinitionLines = new Map();
const returnTypesBySignature = new Map();
const canonicalStorageRpcNames = new Set([
  'get_character_inventory',
  'get_player_homes',
  'reorder_player_homes',
  'save_player_home',
  'delete_player_home',
  'add_home_inventory_item',
  'add_mobile_home_inventory_item',
  'move_inventory_item_to_home',
  'move_home_item_to_inventory',
  'move_item_between_homes',
  'update_house_inventory_item_state',
  'drop_house_inventory_item_quantity',
  'update_mobile_home_item_state',
  'drop_mobile_home_item_quantity',
  'update_inventory_item_state',
  'place_pet_item_in_stable_for_character',
  'place_pet_item_for_character',
  'get_location_wagon_storage',
  'move_inventory_item_to_wagon',
  'move_wagon_item_to_inventory'
]);
const definitionPattern = /create\s+(?:or\s+replace\s+)?function\s+public\.([a-zA-Z0-9_]+)\s*\(([\s\S]*?)\)\s*(?:returns|language)\b/gi;
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

for (const match of sql.matchAll(/create\s+(?:or\s+replace\s+)?function\s+public\.([a-zA-Z0-9_]+)\s*\(([\s\S]*?)\)\s*returns\s+([a-zA-Z0-9_.]+)/gi)) {
  const signature = `${match[1]}(${normalizeSignature(match[2])})`;
  const returnType = match[3]
    .replace(/^int$/i, 'integer')
    .replace(/^decimal$/i, 'numeric')
    .toLowerCase();
  const returnTypes = returnTypesBySignature.get(signature) ?? new Set();
  returnTypes.add(returnType);
  returnTypesBySignature.set(signature, returnTypes);
}

const incompatibleReturnTypes = Array.from(returnTypesBySignature.entries())
  .filter(([, returnTypes]) => returnTypes.size > 1)
  .map(([signature, returnTypes]) => `${signature}: ${Array.from(returnTypes).join(' | ')}`);

const functionLifecycleEvents = [];
for (const match of sql.matchAll(/create\s+(or\s+replace\s+)?function\s+public\.([a-zA-Z0-9_]+)\s*\(([\s\S]*?)\)\s*(?:returns|language)\b/gi)) {
  functionLifecycleEvents.push({
    kind: 'create',
    replace: Boolean(match[1]),
    name: match[2],
    signature: normalizeSignature(match[3]),
    defaultCount: (match[3].match(/\bdefault\b/gi) ?? []).length,
    index: match.index
  });
}
for (const match of sql.matchAll(/drop\s+function\s+(?:if\s+exists\s+)?public\.([a-zA-Z0-9_]+)\s*\(([\s\S]*?)\)\s*(?:cascade|restrict)?\s*;/gi)) {
  functionLifecycleEvents.push({
    kind: 'drop',
    name: match[1],
    signature: normalizeSignature(match[2]),
    index: match.index
  });
}
functionLifecycleEvents.sort((left, right) => left.index - right.index);

const liveFunctionDefinitions = new Map();
const functionReplacementProblems = [];
for (const event of functionLifecycleEvents) {
  const key = `${event.name}(${event.signature})`;
  if (event.kind === 'drop') {
    liveFunctionDefinitions.delete(key);
    continue;
  }
  const previous = liveFunctionDefinitions.get(key);
  if (previous && event.replace && event.defaultCount < previous.defaultCount) {
    functionReplacementProblems.push(
      `${key} removes parameter defaults at line ${lineNumberAt(sql, event.index)}; PostgreSQL requires preserving them or dropping the function first`
    );
  }
  if (previous && !event.replace) {
    functionReplacementProblems.push(`${key} is recreated without a preceding DROP at line ${lineNumberAt(sql, event.index)}`);
  }
  liveFunctionDefinitions.set(key, event);
}

const duplicateOverloads = Array.from(definitions.entries())
  .filter(([name, signatures]) => signatures.size > 1 && !canonicalStorageRpcNames.has(name))
  .map(([name, signatures]) => `${name}: ${Array.from(signatures).join(' | ')}`);

const grants = new Set(
  Array.from(sql.matchAll(/grant\s+execute\s+on\s+function\s+public\.([a-zA-Z0-9_]+)\s*\(/gi))
    .map((match) => match[1])
);
const invalidGrantSignatures = [];
for (const match of sql.matchAll(/grant\s+execute\s+on\s+function\s+public\.([a-zA-Z0-9_]+)\s*\(([\s\S]*?)\)\s+to\b/gi)) {
  const name = match[1];
  const signature = normalizeSignature(match[2]);
  if (definitions.has(name) && !definitions.get(name).has(signature)) {
    invalidGrantSignatures.push(`${name}(${signature}) at line ${lineNumberAt(sql, match.index)}`);
  }
}

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
const missingRlsTables = Array.from(createdPublicTables)
  .filter((name) => !rlsEnabledPublicTables.has(name))
  .sort();
const failures = [];
const partTwoSql = fs.readFileSync(sqlPaths[1], 'utf8');
const canonicalRuntimeMarker = '-- CANONICAL STORAGE RUNTIME START';
const canonicalRuntimeStart = partTwoSql.indexOf(canonicalRuntimeMarker);
const canonicalRuntime = canonicalRuntimeStart >= 0 ? partTwoSql.slice(canonicalRuntimeStart) : '';
const retiredStorageIdentifiers = [
  'player_houses',
  'house_inventory_items',
  'campaign_properties',
  'house_access_permissions',
  'house_unit_access_permissions',
  'mobile_storage_access_permissions',
  'player_main_homes',
  'player_home_display_orders',
  'house_stable_slot_offset'
];
const canonicalStorageRpcs = Array.from(canonicalStorageRpcNames);
const canonicalStorageProblems = [];
const canonicalReturnTypes = new Map([
  ['inventory_item_owner_user_id(public.inventory_items)', 'uuid'],
  ['inventory_portable_property_root(uuid)', 'uuid'],
  ['place_pet_item_in_stable_for_character(uuid, text, text, text, public.item_rarity, numeric, boolean, jsonb, text, text, text, integer, boolean)', 'jsonb'],
  ['place_pet_item_for_character(uuid, text, text, text, public.item_rarity, numeric, boolean, jsonb, text, text, text, integer, boolean)', 'jsonb']
]);

if (canonicalRuntimeStart < 0) {
  canonicalStorageProblems.push('canonical runtime marker is missing');
} else {
  for (const identifier of retiredStorageIdentifiers) {
    const match = new RegExp(`\\b${identifier}\\b`, 'i').exec(canonicalRuntime);
    if (match) {
      canonicalStorageProblems.push(`${identifier} is referenced after the canonical runtime boundary at line ${lineNumberAt(partTwoSql, canonicalRuntimeStart + match.index)}`);
    }
  }
  for (const match of canonicalRuntime.matchAll(/(?:slot_index|slot|stable_slot)\s*(?:\+|-)\s*1000|1000\s*(?:\+|-)\s*(?:slot_index|slot|stable_slot)/gi)) {
    canonicalStorageProblems.push(`stable-slot offset arithmetic appears at line ${lineNumberAt(partTwoSql, canonicalRuntimeStart + match.index)}`);
  }
  for (const rpcName of canonicalStorageRpcs) {
    const count = Array.from(canonicalRuntime.matchAll(new RegExp(`create\\s+(?:or\\s+replace\\s+)?function\\s+public\\.${rpcName}\\s*\\(`, 'gi'))).length;
    if (count !== 1) canonicalStorageProblems.push(`${rpcName} has ${count} canonical runtime definitions; expected exactly 1`);
  }
  for (const [signature, expectedReturnType] of canonicalReturnTypes) {
    const returnTypes = returnTypesBySignature.get(signature);
    if (!returnTypes?.has(expectedReturnType)) {
      canonicalStorageProblems.push(`${signature} must return ${expectedReturnType}`);
    }
  }
}
const requiredCityPayloadFields = [
  'description',
  'primaryColor',
  'secondaryColor',
  'accentColor',
  'visibleToPlayers',
  'currentResidence',
  'showUnderConstruction'
];
const cityContractProblems = [];

for (const sqlPath of sqlPaths) {
  const source = fs.readFileSync(sqlPath, 'utf8');
  const serializer = source.match(/create\s+or\s+replace\s+function\s+public\.city_record_to_json[\s\S]*?\bas\s+\$\$([\s\S]*?)\$\$;/i)?.[1] ?? '';
  const cityLoader = source.match(/create\s+or\s+replace\s+function\s+public\.get_discovered_cities[\s\S]*?\bas\s+\$\$([\s\S]*?)\$\$;/i)?.[1] ?? '';
  const label = path.basename(sqlPath);
  const missingFields = requiredCityPayloadFields.filter((field) => !serializer.includes(`'${field}'`));
  if (missingFields.length) cityContractProblems.push(`${label}: city payload is missing ${missingFields.join(', ')}`);
  if (!cityLoader.includes("'constructionProjects'")) cityContractProblems.push(`${label}: discovered cities payload is missing constructionProjects`);
}

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

const compositeIntoProblems = [];
const functionBodyPattern = /create\s+or\s+replace\s+function\s+public\.([a-zA-Z0-9_]+)[\s\S]*?\bas\s+\$\$([\s\S]*?)\$\$;/gi;
for (const functionMatch of sql.matchAll(functionBodyPattern)) {
  const functionName = functionMatch[1];
  const body = functionMatch[2];
  const rowVariables = new Set(
    Array.from(body.matchAll(/\b([a-zA-Z0-9_]+)\s+public\.[a-zA-Z0-9_]+%rowtype\b/gi))
      .map((match) => match[1].toLowerCase())
  );
  if (!rowVariables.size) continue;

  for (const intoMatch of body.matchAll(/\bselect\b[\s\S]*?\binto\s+([a-zA-Z0-9_]+(?:\s*,\s*[a-zA-Z0-9_]+)+)\s+from\b/gi)) {
    const targets = intoMatch[1].split(',').map((target) => target.trim().toLowerCase());
    const compositeTargets = targets.filter((target) => rowVariables.has(target));
    if (!compositeTargets.length) continue;
    const bodyOffset = functionMatch.index + functionMatch[0].indexOf(body) + intoMatch.index;
    compositeIntoProblems.push(
      `${functionName}: composite row variable ${compositeTargets.join(', ')} appears in a multi-item INTO list at line ${lineNumberAt(sql, bodyOffset)}`
    );
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

if (missingRlsTables.length) {
  failures.push(`Public tables without row-level security:\n${missingRlsTables.map((name) => `- ${name}`).join('\n')}`);
}

if (grantsWithoutDefinitions.length) {
  failures.push(`Execute grants without SQL definitions:\n${grantsWithoutDefinitions.map((entry) => `- ${entry}`).join('\n')}`);
}

if (invalidGrantSignatures.length) {
  failures.push(`Execute grants without matching function signatures:\n${invalidGrantSignatures.map((entry) => `- ${entry}`).join('\n')}`);
}

if (incompatibleReturnTypes.length) {
  failures.push(`Function signatures with incompatible return types:\n${incompatibleReturnTypes.map((entry) => `- ${entry}`).join('\n')}`);
}

if (functionReplacementProblems.length) {
  failures.push(`Unsafe PostgreSQL function replacements:\n${functionReplacementProblems.map((entry) => `- ${entry}`).join('\n')}`);
}

if (grantOrderProblems.length) {
  failures.push(`Execute grants before SQL definitions:\n${grantOrderProblems.map((entry) => `- ${entry}`).join('\n')}`);
}

if (destructiveSeedProblems.length) {
  failures.push(`City/shop seed reset patterns found:\n${destructiveSeedProblems.map((entry) => `- ${entry}`).join('\n')}`);
}

if (compositeIntoProblems.length) {
  failures.push(`Invalid PostgreSQL composite-row INTO lists:\n${compositeIntoProblems.map((entry) => `- ${entry}`).join('\n')}`);
}

if (cityContractProblems.length) {
  failures.push(`Incomplete discovered-city SQL contracts:\n${cityContractProblems.map((entry) => `- ${entry}`).join('\n')}`);
}

if (canonicalStorageProblems.length) {
  failures.push(`Canonical storage contract violations:\n${canonicalStorageProblems.map((entry) => `- ${entry}`).join('\n')}`);
}

if (failures.length) {
  console.error(failures.join('\n\n'));
  process.exit(1);
}

console.log(`SQL validation passed: ${definitions.size} functions, ${rpcCalls.size} app RPC calls checked.`);
