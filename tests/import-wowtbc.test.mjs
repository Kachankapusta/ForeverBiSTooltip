import { test } from 'node:test';
import assert from 'node:assert/strict';
import { discoverSpecs, normalizePage, buildSnapshot, renderDatabase } from '../tools/import-wowtbc.mjs';

function fixture() {
  return { result: { pageContext: {
    isClassicPlus: true, spec: 'fury-warrior',
    bisList: { class: 'warrior', spec: 'fury',
      'pre-raid': { gear: { head: [{ id: 12640, alternative: false }, { id: 20521, alternative: true }] }, enchants: { head: { id: 15397, name: 'Arcanum' } } },
      'pre-raid-realistic': { gear: { head: [{ id: 20521, alternative: false }] } },
      caps: { 20: { finger: [20521, 12640], 'main-hand': [12640] } },
    },
    gearData: [{ id: 12640, name: 'Lionheart Helm', source: 'Blacksmithing' }, { id: 20521, name: 'Fury Visor' }],
  } } };
}

test('discovers only Forever specialization pages and removes duplicate navigation links', () => {
  assert.deepEqual(discoverSpecs('<a href="/warcraftforever/bis-list/fury-warrior/">x</a><a href="/tbc/bis-list/arms-warrior/">x</a><a href="/warcraftforever/bis-list/fury-warrior/">x</a>'), ['fury-warrior']);
  assert.throws(() => discoverSpecs('<html>Maintenance</html>'), /no specialization/);
});

test('preserves explicit main picks, alternatives and Realistic separately', () => {
  const page = normalizePage('fury-warrior', fixture());
  assert.deepEqual(page.stages['pre-raid'].slots.head, [{ id: 12640, preferred: true }, { id: 20521, preferred: false }]);
  assert.equal(page.stages['pre-raid-realistic'].slots.head[0].id, 20521);
  assert.deepEqual(page.stages['pre-raid'].enchants.head, { id: 15397, name: 'Arcanum', kind: 'spell' });
});

test('joins direct enchant recipes while keeping effect, ingredients and formula identities separate', () => {
  const data = fixture();
  const ctx = data.result.pageContext;
  ctx.bisList['pre-raid'].enchants.head = { id: 1248805, name: 'Enchant Weapon - Revelation' };
  ctx.enchantsData = [{ id: 1248805, name: 'Enchant Weapon - Revelation', source: 'Enchanting',
    source_type: 'Crafted', icon: 'spell_holy_greaterheal', text: 'Revelation', reagents: [{ name: 'Soul Dust', count: 8 }] }];
  const recipes = new Map([['enchanting', [{ id: 1248805, name: 'Enchant Weapon - Revelation',
    text: 'Can grant Revelation after a non-critical spell hit.', reagents: [{ id: 11083, name: 'Soul Dust', count: 8 }],
    tools: ['Runed Arcanite Rod', '', null], taught_by: [{ id: 249481 }] }]]]);
  const enchant = normalizePage('fury-warrior', data, recipes).stages['pre-raid'].enchants.head;
  assert.deepEqual(enchant, {
    id: 1248805, name: 'Enchant Weapon - Revelation', kind: 'spell', spellID: 1248805,
    recipeID: 1248805, recipeItemID: 249481, source: 'Enchanting', sourceType: 'Crafted',
    icon: 'spell_holy_greaterheal', effect: 'Can grant Revelation after a non-critical spell hit.',
    tools: ['Runed Arcanite Rod'],
    reagents: [{ id: 11083, name: 'Soul Dust', count: 8 }],
  });
});

test('recognizes the crafted output only when its name and material counts match the enhancement', () => {
  const data = fixture();
  const ctx = data.result.pageContext;
  ctx.bisList['pre-raid'].enchants.head = { id: 1254770, name: 'Mystic Rugged Armor Kit' };
  ctx.enchantsData = [{ id: 1254770, name: 'Mystic Rugged Armor Kit', source: 'Leatherworking', text: 'Spell Power +6 and Armor +40',
    reagents: [{ name: 'Rugged Armor Kit', count: 1 }] }];
  const recipe = { id: 1254966, name: 'Mystic Rugged Armor Kit', item: { id: 252487, name: 'Mystic Rugged Armor Kit', use: 'Usable on items level $ecim and above.' },
    reagents: [{ id: 15564, name: 'Rugged Armor Kit', count: 1 }] };
  const recipes = new Map([['leatherworking', [recipe]]]);
  const enchant = normalizePage('fury-warrior', data, recipes).stages['pre-raid'].enchants.head;
  assert.equal(enchant.kind, 'item');
  assert.equal(enchant.id, 1254770);
  assert.equal(enchant.itemID, 252487);
  assert.equal(enchant.recipeID, 1254966);
  assert.equal(enchant.effect, 'Spell Power +6 and Armor +40');
  assert.deepEqual(enchant.reagents, [{ id: 15564, name: 'Rugged Armor Kit', count: 1 }]);
  recipe.reagents[0].count = 2;
  const unmatched = normalizePage('fury-warrior', data, recipes).stages['pre-raid'].enchants.head;
  assert.equal(unmatched.itemID, undefined);
  assert.deepEqual(unmatched.reagents, [{ name: 'Rugged Armor Kit', count: 1 }]);
});

test('separates a quest turn-in from crafting and uses the item matching the effect spell', () => {
  const data = fixture();
  const ctx = data.result.pageContext;
  ctx.bisList['pre-raid'].enchants.head.name = 'Lesser Arcanum of Voracity';
  ctx.enchantsData = [{ id: 15397, name: 'Lesser Arcanum of Voracity', source: 'Libram of Voracity',
    source_type: 'Quest', text: 'Strength +8', zone: 'Burning Steppes', reagents: [] }];
  const enchant = normalizePage('fury-warrior', data).stages['pre-raid'].enchants.head;
  assert.equal(enchant.kind, 'item');
  assert.equal(enchant.itemID, 11645);
  assert.equal(enchant.spellID, 15397);
  assert.equal(enchant.questID, 4484);
  assert.equal(enchant.requiredGold, 30);
  assert.equal(enchant.reagents, undefined);
  assert.deepEqual(enchant.requirements, [
    { id: 11737, name: 'Libram of Voracity', count: 1 },
    { id: 11754, name: 'Black Diamond', count: 1 },
    { id: 11951, name: 'Whipper Root Tuber', count: 4, bindOnPickup: true },
    { id: 11563, name: 'Crystal Force', count: 4, bindOnPickup: true },
  ]);
});

test('imports only Pre-Raid variants and does not invent a main pick from list position', () => {
  const data = fixture();
  delete data.result.pageContext.bisList['pre-raid'].gear.head[0].alternative;
  const page = normalizePage('fury-warrior', data);
  assert.deepEqual(Object.keys(page.stages), ['pre-raid', 'pre-raid-realistic']);
  assert.equal(page.stages['pre-raid'].slots.head[0].preferred, false);
});

test('rejects another expansion, unknown slots, broken IDs and missing referenced metadata', () => {
  const wrong = fixture(); wrong.result.pageContext.isClassicPlus = false;
  assert.throws(() => normalizePage('fury-warrior', wrong), /Unexpected Forever/);
  const slot = fixture(); slot.result.pageContext.bisList['pre-raid'].gear.unknown = [12640];
  assert.throws(() => normalizePage('fury-warrior', slot), /Unknown slot/);
  const broken = fixture(); broken.result.pageContext.bisList['pre-raid'].gear.head[0].id = '12640';
  assert.throws(() => normalizePage('fury-warrior', broken), /Invalid item ID/);
  const missing = fixture(); missing.result.pageContext.gearData.pop();
  assert.throws(() => normalizePage('fury-warrior', missing), /Missing item metadata/);
});

test('normalizes multiword source specializations without changing their page identity', () => {
  const data = fixture();
  data.result.pageContext.spec = 'feral-tank-druid';
  data.result.pageContext.bisList.class = 'druid';
  data.result.pageContext.bisList.spec = 'feral tank';
  const page = normalizePage('feral-tank-druid', data);
  assert.equal(page.spec.label, 'Feral Tank');
  assert.equal(page.spec.class, 'DRUID');
});

test('preserves optional per-slot gem recommendations and rejects malformed gem data', () => {
  const data = fixture();
  data.result.pageContext.bisList['pre-raid'].gems = { head: [{ id: 23094, name: 'A gem' }, 23095] };
  const page = normalizePage('fury-warrior', data);
  assert.deepEqual(page.stages['pre-raid'].gems.head, [{ id: 23094, name: 'A gem' }, { id: 23095 }]);
  assert.equal(page.items[23094].name, 'A gem');
  data.result.pageContext.bisList['pre-raid'].gems.head = [{ id: 'bad' }];
  assert.throws(() => normalizePage('fury-warrior', data), /Invalid item ID/);
});

test('preserves explicitly supplied gem recipes and normalizes reagent entries', () => {
  const data = fixture();
  data.result.pageContext.bisList['pre-raid'].gems = { head: [
    { id: 23094, name: 'A gem', recipeID: 28903, reagents: [{ id: 23077, name: 'Blood Garnet', count: 1, extra: true }] },
    { id: 23095, recipeID: 0, reagents: [{ id: 23077, name: 'Blood Garnet', count: -1 }] },
  ] };
  const page = normalizePage('fury-warrior', data);
  assert.deepEqual(page.stages['pre-raid'].gems.head, [
    { id: 23094, name: 'A gem', recipeID: 28903, reagents: [{ id: 23077, name: 'Blood Garnet', count: 1 }] },
    { id: 23095 },
  ]);
  assert.match(renderDatabase(buildSnapshot([page])), /\["recipeID"\]=28903,\["reagents"\]=\{\{\["id"\]=23077/);
});

test('enriches a gem when just one known recipe crafts its exact item ID', () => {
  const data = fixture();
  data.result.pageContext.bisList['pre-raid'].gems = { head: [23094, 23095] };
  const reagents = [{ id: 23077, name: 'Blood Garnet', count: 1 }];
  const recipes = new Map([['profession', [
    { id: 28903, item: { id: 23094 }, reagents },
    { id: 28905, item: { id: 23095 }, reagents },
    { id: 28906, item: { id: 23095 }, reagents },
  ]]]);
  const page = normalizePage('fury-warrior', data, recipes);
  assert.deepEqual(page.stages['pre-raid'].gems.head, [
    { id: 23094, recipeID: 28903, reagents },
    { id: 23095 },
  ]);
});

test('rejects incomplete/duplicate snapshots and escapes source strings in Lua', () => {
  const page = normalizePage('fury-warrior', fixture());
  assert.throws(() => buildSnapshot([]), /empty database/);
  assert.throws(() => buildSnapshot([page, page]), /Duplicate specialization/);
  page.items[12640].name = 'A "helm"\\path\nnext';
  const output = renderDatabase(buildSnapshot([page], '2026-11-22'));
  assert.match(output, /A \\"helm\\"\\\\path\\nnext/);
  assert.match(output, /\["updated"\]="2026-11-22"/);
  assert.doesNotMatch(output, /\["rank"\]/);
});
