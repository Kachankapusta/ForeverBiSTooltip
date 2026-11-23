import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtemp, rmdir, unlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { renderDatabase } from '../tools/import-wowtbc.mjs';
import { dataHash, uploadRelease } from '../tools/release-tools.mjs';

function database(date = '2026-11-23', item = 'Helm') {
  return renderDatabase({
    source: { name: 'wowtbc.gg', url: 'https://wowtbc.gg/warcraftforever/bis-list/', updated: date, schema: 1, specCount: 1, itemCount: 1 },
    specs: [{ id: 'fury-warrior', class: 'WARRIOR', label: 'Fury' }],
    lists: { 'fury-warrior': { stages: { 'pre-raid': { slots: { head: [{ id: 1, preferred: true }] } } } } },
    items: { 1: { name: item, updated: '2025-01-01' } },
  });
}

test('hashes the database while ignoring only the generated ns.Source update date', () => {
  const first = database();
  const expected = createHash('sha256').update(first.replace(',["updated"]="2026-11-23"', '')).digest('hex');
  assert.equal(dataHash(first), expected);
  assert.equal(dataHash(database('2026-11-24')), expected);
  assert.notEqual(dataHash(database('2026-11-23', 'Another helm')), expected);
  assert.notEqual(dataHash(first.replace('["updated"]="2025-01-01"', '["updated"]="2025-01-02"')), expected);
  assert.notEqual(dataHash(first.replace('["schema"]=1', '["schema"]=2')), expected);
});

test('refuses missing, duplicate and malformed database headers', () => {
  const valid = database();
  const header = valid.split('\n').find(line => line.startsWith('ns.Source'));
  assert.throws(() => dataHash(valid.replace(header, '')), /ns.Source header/);
  assert.throws(() => dataHash(`${valid}${header}\n`), /ns.Source header/);
  assert.throws(() => dataHash(valid.replace('["updated"]=', '["updated"]==')), /ns.Source header/);
  assert.throws(() => dataHash(database('2026-02-30')), /Invalid update date/);
});

async function releaseFixture(t) {
  const directory = await mkdtemp(join(tmpdir(), 'fbt-release-test-'));
  const zipPath = join(directory, 'ForeverBiSTooltip-0.1.1.zip');
  const changelogPath = join(directory, 'changes.md');
  const zip = Buffer.from([0x50, 0x4b, 0x03, 0x04, 0x01]);
  const changelog = '# Database update\n';
  await Promise.all([writeFile(zipPath, zip), writeFile(changelogPath, changelog)]);
  t.after(async () => {
    await Promise.all([unlink(zipPath), unlink(changelogPath)]);
    await rmdir(directory);
  });
  return { args: [zipPath, '0.1.1', changelogPath], zip, changelog };
}

const env = { CURSEFORGE_PROJECT_ID: '42', CF_API_TOKEN: 'test-secret' };
const authorAPI = 'https://wow.curseforge.com/api';

test('sends the archive and markdown metadata as a Forever release', async t => {
  const { args, zip, changelog } = await releaseFixture(t);
  const calls = [];
  const id = await uploadRelease(...args, env, async (url, options) => {
    calls.push(url);
    assert.equal(options.headers['X-Api-Token'], env.CF_API_TOKEN);
    assert.equal(options.redirect, 'error');
    assert(options.signal instanceof AbortSignal);
    if (url.endsWith('/game/versions')) {
      return Response.json([{ id: 23, name: '1.60.1' }, { id: 24, name: '1.60.2' }]);
    }
    assert.equal(options.method, 'POST');
    assert.deepEqual(JSON.parse(options.body.get('metadata')), {
      changelog, changelogType: 'markdown', displayName: 'Forever BiS Tooltip 0.1.1',
      gameVersions: [23], releaseType: 'release',
    });
    const archive = options.body.get('file');
    assert.equal(archive.name, 'ForeverBiSTooltip-0.1.1.zip');
    assert.deepEqual(Buffer.from(await archive.arrayBuffer()), zip);
    return Response.json({ id: 144 });
  });
  assert.equal(id, 144);
  assert.deepEqual(calls, [`${authorAPI}/game/versions`, `${authorAPI}/projects/42/upload-file`]);
});

test('validates an explicit game version ID before uploading', async t => {
  const { args } = await releaseFixture(t);
  const versions = [{ id: 23, name: '1.60.1' }, { id: 24, name: '1.60.1' }, { id: 25, name: '11.0.0' }];
  const catalogOnly = async url => {
    assert.equal(url, `${authorAPI}/game/versions`);
    return Response.json(versions);
  };
  await assert.rejects(uploadRelease(...args, env, catalogOnly), /could not be resolved uniquely/);
  await assert.rejects(uploadRelease(...args, { ...env, CURSEFORGE_GAME_VERSION_ID: '25' }, catalogOnly), /could not be resolved uniquely/);
  const id = await uploadRelease(...args, { ...env, CURSEFORGE_GAME_VERSION_ID: '24' }, async (url, options) => {
    if (url.endsWith('/game/versions')) return Response.json(versions);
    assert.deepEqual(JSON.parse(options.body.get('metadata')).gameVersions, [24]);
    return Response.json({ id: 144 });
  });
  assert.equal(id, 144);
});

test('reports failed uploads without echoing remote messages or retrying the POST', async t => {
  const { args } = await releaseFixture(t);
  let uploads = 0;
  await assert.rejects(uploadRelease(...args, env, async url => {
    if (url.endsWith('/game/versions')) return Response.json([{ id: 23, name: '1.60.1' }]);
    uploads++;
    return Response.json({ detail: env.CF_API_TOKEN }, { status: 503 });
  }), { message: 'CurseForge upload: HTTP 503' });
  assert.equal(uploads, 1);
});
