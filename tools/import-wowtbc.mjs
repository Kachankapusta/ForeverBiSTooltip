import { readFile, writeFile, rename, mkdir } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const SOURCE = 'https://wowtbc.gg';
export const INDEX_PATH = '/warcraftforever/bis-list/';
const CLASSES = new Set(['DRUID', 'HUNTER', 'MAGE', 'PALADIN', 'PRIEST', 'ROGUE', 'SHAMAN', 'WARLOCK', 'WARRIOR']);
const PROFESSIONS = ['enchanting', 'leatherworking', 'engineering'];
const ARCANUM_ITEMS = new Map([
  [15397, 11645], [15400, 11646], [15402, 11647], [15404, 11648], [15406, 11649], [22844, 18330],
]);
// Forever quest objectives: https://www.wowhead.com/forever/quest=4484 and quest=7484.
const LIBRAMS = {
  'Libram of Voracity': {
    questID: 4484, requiredGold: 30,
    requirements: [
      { id: 11737, name: 'Libram of Voracity', count: 1 },
      { id: 11754, name: 'Black Diamond', count: 1 },
      { id: 11951, name: 'Whipper Root Tuber', count: 4, bindOnPickup: true },
      { id: 11563, name: 'Crystal Force', count: 4, bindOnPickup: true },
    ],
  },
  'Libram of Focus': {
    questID: 7484,
    requirements: [
      { id: 18333, name: 'Libram of Focus', count: 1 },
      { id: 18335, name: 'Pristine Black Diamond', count: 1 },
      { id: 14344, name: 'Large Brilliant Shard', count: 4 },
      { id: 12753, name: 'Skin of Shadow', count: 2, bindOnPickup: true },
    ],
  },
};
const SLOT_MAP = {
  head: 'head', neck: 'neck', shoulder: 'shoulder', back: 'back', chest: 'chest',
  wrist: 'wrist', hands: 'hands', waist: 'waist', legs: 'legs', feet: 'feet',
  'finger 1': 'finger1', 'finger 2': 'finger2', finger: 'finger',
  'trinket 1': 'trinket1', 'trinket 2': 'trinket2', trinket: 'trinket',
  weapon: 'weapon', 'main-hand': 'weapon', 'off hand': 'offhand', 'off-hand': 'offhand', ranged: 'ranged',
};

function itemID(value, location) {
  if (!Number.isSafeInteger(value) || value < 1) throw new Error(`Invalid item ID at ${location}: ${value}`);
  return value;
}

export function discoverSpecs(html) {
  const paths = [...html.matchAll(/href=["'](\/warcraftforever\/bis-list\/([a-z-]+)\/)["']/g)];
  const specs = [...new Set(paths.map(match => match[2]))];
  if (!specs.length) throw new Error('The Forever index contains no specialization links');
  return specs;
}

function label(value) {
  return value.split(/[-_\s]+/).map(part => part === 'dps' ? 'DPS' : part[0].toUpperCase() + part.slice(1)).join(' ');
}

function validID(value) {
  return Number.isSafeInteger(value) && value > 0;
}

function normalizeReagents(reagents) {
  if (!Array.isArray(reagents) || !reagents.every(entry =>
    typeof entry?.name === 'string' && entry.name.trim() && validID(entry.count))) return;
  return reagents.map(({ id, name, count }) => validID(id) ? { id, name, count } : { name, count });
}

function reagentKey(reagents) {
  return JSON.stringify(reagents.map(({ name, count }) => [name, count]).sort(([left], [right]) => left.localeCompare(right)));
}

function matchingRecipe(enchant, recipes, reagents) {
  const matches = recipes.filter(recipe => recipe.name === enchant.name && validID(recipe.id));
  const exact = matches.find(recipe => recipe.id === enchant.id);
  if (exact) return exact;
  if (!reagents?.length) return;
  const key = reagentKey(reagents);
  const outputs = matches.filter(recipe => {
    const materials = normalizeReagents(recipe.reagents);
    return recipe.item?.name === enchant.name && validID(recipe.item.id) && materials && reagentKey(materials) === key;
  });
  if (outputs.length === 1) return outputs[0];
}

function enchantDetails(ref, details, professionRecipes, location) {
  const id = itemID(ref.id, location);
  const enchant = { id, name: ref.name, kind: 'spell' };
  if (!details) return enchant;

  for (const [key, value] of Object.entries({ icon: details.icon, source: details.source, sourceType: details.source_type, zone: details.zone, effect: details.text })) {
    if (typeof value === 'string' && value.trim()) enchant[key] = value;
  }

  const reagents = normalizeReagents(details.reagents);
  const recipe = matchingRecipe(details, professionRecipes.get(details.source?.toLowerCase()) ?? [], reagents);
  if (recipe) {
    enchant.recipeID = recipe.id;
    if (Array.isArray(recipe.tools)) {
      const tools = recipe.tools.filter(tool => typeof tool === 'string' && tool.trim());
      if (tools.length) enchant.tools = tools;
    }
    const formulas = recipe.taught_by?.filter(entry => validID(entry.id));
    if (formulas?.length === 1) enchant.recipeItemID = formulas[0].id;
    if (validID(recipe.item?.id)) {
      enchant.kind = 'item';
      enchant.itemID = recipe.item.id;
    } else {
      enchant.spellID = recipe.id;
    }
    const effect = recipe.text || recipe.item?.use;
    if (typeof effect === 'string' && effect.trim() && !effect.includes('$')) enchant.effect = effect;
  }

  const recipeReagents = normalizeReagents(recipe?.reagents);
  if (recipeReagents) enchant.reagents = recipeReagents;
  else if (reagents?.length) enchant.reagents = reagents;

  const libram = details.source_type === 'Quest' && LIBRAMS[details.source];
  if (libram && ARCANUM_ITEMS.has(id)) {
    Object.assign(enchant, libram, { kind: 'item', itemID: ARCANUM_ITEMS.get(id), spellID: id });
  }
  return enchant;
}

export function normalizePage(slug, page, professionRecipes = new Map()) {
  const context = page?.result?.pageContext;
  if (!context?.isClassicPlus || context.spec !== slug || !context.bisList || !Array.isArray(context.gearData)) {
    throw new Error(`Unexpected Forever page schema: ${slug}`);
  }
  const bis = context.bisList;
  const classID = String(bis.class).toUpperCase();
  if (!CLASSES.has(classID)) throw new Error(`Unsupported class: ${classID}`);
  const expectedSlug = `${bis.spec}-${bis.class}`.toLowerCase().replace(/[\s_]+/g, '-');
  if (slug !== expectedSlug) throw new Error(`Specialization mismatch: ${slug} (${expectedSlug})`);
  const available = new Map(context.gearData.map(item => [item.id, item]));
  const enchantByID = new Map((context.enchantsData || []).map(entry => [entry.id, entry]));
  const items = {};
  const stages = {};

  function convertSlots(gear, stageID) {
    if (!gear || typeof gear !== 'object' || Array.isArray(gear)) throw new Error(`Missing gear: ${slug}/${stageID}`);
    const slots = {};
    for (const [slotName, entries] of Object.entries(gear)) {
      const slot = SLOT_MAP[slotName];
      if (!slot || !Array.isArray(entries)) throw new Error(`Unknown slot/schema: ${slug}/${stageID}/${slotName}`);
      const seen = new Set();
      const converted = [];
      for (const entry of entries) {
        const id = itemID(typeof entry === 'number' ? entry : entry?.id, `${slug}/${stageID}/${slotName}`);
        if (seen.has(id)) continue;
        seen.add(id);
        const item = available.get(id);
        if (!item?.name) throw new Error(`Missing item metadata: ${slug}/${stageID}/${id}`);
        items[id] = {
          name: item.name,
          icon: item.icon || 'inv_misc_questionmark',
          rarity: item.rarity || 'common',
          source: item.source || '',
          sourceType: item.source_type || '',
        };
        converted.push({ id, preferred: typeof entry === 'object' && entry.alternative === false });
      }
      if (converted.length) slots[slot] = converted;
    }
    if (!Object.keys(slots).length) throw new Error(`Empty gear: ${slug}/${stageID}`);
    return slots;
  }

  for (const [key, value] of Object.entries(bis)) {
    if (!value?.gear) continue;
    if (key !== 'pre-raid' && key !== 'pre-raid-realistic') throw new Error(`Unknown phase: ${slug}/${key}`);
    const enchants = {};
    for (const [slotName, enchant] of Object.entries(value.enchants || {})) {
      if (!enchant) continue;
      const slot = SLOT_MAP[slotName];
      if (!slot || !enchant.name) throw new Error(`Unknown enchant schema: ${slug}/${key}/${slotName}`);
      const details = enchantByID.get(enchant.id);
      enchants[slot] = enchantDetails(enchant, details?.name === enchant.name ? details : undefined, professionRecipes, `${slug}/${key}/enchant`);
    }
    const stage = { slots: convertSlots(value.gear, key), enchants };
    if (value.gems) {
      const gems = {};
      const recipes = [...professionRecipes.values()].flat();
      for (const [slotName, recommendations] of Object.entries(value.gems)) {
        const slot = SLOT_MAP[slotName];
        if (!slot || !Array.isArray(recommendations)) throw new Error(`Unknown gem schema: ${slug}/${key}/${slotName}`);
        gems[slot] = recommendations.map(entry => {
          const id = itemID(typeof entry === 'number' ? entry : entry?.id, `${slug}/${key}/gem`);
          const name = typeof entry === 'object' ? entry.name : available.get(id)?.name;
          if (name && !items[id]) items[id] = { name };
          const gem = name ? { id, name } : { id };
          if (validID(entry?.recipeID)) gem.recipeID = entry.recipeID;
          const matches = recipes.filter(recipe => recipe?.item?.id === id && validID(recipe.id)
            && (gem.recipeID === undefined || recipe.id === gem.recipeID));
          const recipe = matches.length === 1 ? matches[0] : undefined;
          if (recipe) gem.recipeID = recipe.id;
          const reagents = normalizeReagents(entry?.reagents) || normalizeReagents(recipe?.reagents);
          if (reagents?.length) gem.reagents = reagents;
          return gem;
        });
      }
      stage.gems = gems;
    }
    stages[key] = stage;
  }
  if (!stages['pre-raid']) throw new Error(`Missing Pre-Raid list: ${slug}`);
  return { spec: { id: slug, class: classID, label: label(bis.spec) }, stages, items };
}

export function buildSnapshot(pages, updated = new Date().toISOString().slice(0, 10)) {
  if (!pages.length) throw new Error('Refusing to build an empty database');
  const specs = [];
  const lists = {};
  const items = {};
  for (const page of pages) {
    if (lists[page.spec.id]) throw new Error(`Duplicate specialization: ${page.spec.id}`);
    specs.push(page.spec);
    lists[page.spec.id] = { stages: page.stages };
    Object.assign(items, page.items);
  }
  return {
    source: { name: 'wowtbc.gg', url: SOURCE + INDEX_PATH, updated, schema: 1, specCount: specs.length, itemCount: Object.keys(items).length },
    specs, lists, items,
  };
}

function luaString(value) {
  return '"' + value.replace(/[\\"\x00-\x1f\x7f]/g, char => {
    if (char === '\\') return '\\\\';
    if (char === '"') return '\\"';
    if (char === '\n') return '\\n';
    if (char === '\r') return '\\r';
    if (char === '\t') return '\\t';
    return '\\' + String(char.charCodeAt(0)).padStart(3, '0');
  }) + '"';
}

export function lua(value) {
  if (typeof value === 'string') return luaString(value);
  if (typeof value === 'boolean') return String(value);
  if (typeof value === 'number' && Number.isFinite(value)) return String(value);
  if (Array.isArray(value)) return '{' + value.map(lua).join(',') + '}';
  if (value && typeof value === 'object') return '{' + Object.entries(value).map(([key, entry]) => `[${/^\d+$/.test(key) ? key : luaString(key)}]=${lua(entry)}`).join(',') + '}';
  throw new Error('Unsupported Lua value');
}

export function renderDatabase(snapshot) {
  const lines = ['-- Generated from public WoW Forever lists at wowtbc.gg. Update with tools/import-wowtbc.mjs.', 'local _, ns = ...', '', `ns.Source = ${lua(snapshot.source)}`, `ns.Specs = ${lua(snapshot.specs)}`, '', 'ns.Items = {'];
  for (const id of Object.keys(snapshot.items).sort((a, b) => Number(a) - Number(b))) lines.push(`    [${id}] = ${lua(snapshot.items[id])},`);
  lines.push('}', '', 'ns.Lists = {');
  for (const spec of snapshot.specs) lines.push(`    [${luaString(spec.id)}] = ${lua(snapshot.lists[spec.id])},`);
  lines.push('}', '');
  return lines.join('\n');
}

async function get(url, json = false) {
  const response = await fetch(url, { signal: AbortSignal.timeout(30000), headers: { 'User-Agent': 'ForeverBiSTooltip data importer (personal addon)' } });
  if (!response.ok) throw new Error(`${response.status} ${url}`);
  return json ? response.json() : response.text();
}

async function main() {
  const output = resolve(dirname(fileURLToPath(import.meta.url)), '..', 'Data.lua');
  const slugs = discoverSpecs(await get(SOURCE + INDEX_PATH));
  const professionRecipes = new Map(await Promise.all(PROFESSIONS.map(async profession => {
    const page = await get(`${SOURCE}/page-data/warcraftforever/professions/${profession}/page-data.json`, true);
    const categories = page?.result?.pageContext?.profession?.categories;
    if (!Array.isArray(categories)) throw new Error(`Unexpected Forever profession schema: ${profession}`);
    return [profession, categories.flatMap(category => category.recipes)];
  })));
  const pages = [];
  for (const slug of slugs) {
    const page = await get(`${SOURCE}/page-data${INDEX_PATH}${slug}/page-data.json`, true);
    pages.push(normalizePage(slug, page, professionRecipes));
    console.log(`Imported ${slug} (${pages.length}/${slugs.length})`);
  }
  const snapshot = buildSnapshot(pages);
  const previous = await readFile(output, 'utf8').catch(error => { if (error.code !== 'ENOENT') throw error; return ''; });
  const previousCount = Number(previous.match(/\["specCount"\]=(\d+)/)?.[1] || 0);
  if (snapshot.specs.length < previousCount) throw new Error(`Index shrank from ${previousCount} to ${snapshot.specs.length}; database was not replaced`);
  await mkdir(dirname(output), { recursive: true });
  await writeFile(output + '.tmp', renderDatabase(snapshot), 'utf8');
  await rename(output + '.tmp', output);
  console.log(`Saved ${snapshot.source.specCount} specializations, ${snapshot.source.itemCount} items to ${output}`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
