import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { basename, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const CURSEFORGE = 'https://wow.curseforge.com/api';
const GAME_VERSION = '1.60.1';
const SOURCE_HEADER = /^(ns\.Source = \{\["name"\]="[^"\r\n]+",\["url"\]="[^"\r\n]+"),\["updated"\]="(\d{4}-\d{2}-\d{2})"(,\["schema"\]=[1-9]\d*,\["specCount"\]=[1-9]\d*,\["itemCount"\]=[1-9]\d*\})$/;

export function dataHash(database) {
  const headers = [...database.matchAll(/^[ \t]*ns\.Source[ \t]*=[^\r\n]*/gm)];
  const [header] = headers;
  const parsed = headers.length === 1 && header[0].match(SOURCE_HEADER);
  if (!parsed) throw new Error('Invalid ns.Source header in Data.lua');
  const [, beforeDate, date, afterDate] = parsed;
  const parsedDate = new Date(`${date}T00:00:00Z`);
  if (!Number.isFinite(parsedDate.valueOf()) || parsedDate.toISOString().slice(0, 10) !== date) {
    throw new Error('Invalid update date in the ns.Source header');
  }
  const start = header.index;
  return createHash('sha256')
    .update(database.slice(0, start))
    .update(beforeDate + afterDate)
    .update(database.slice(start + header[0].length))
    .digest('hex');
}

function isID(value) {
  return Number.isSafeInteger(value) && value > 0;
}

function parseID(value, name) {
  const id = Number(value);
  if (!/^[1-9]\d*$/.test(value ?? '') || !isID(id)) throw new Error(`Set ${name} to a positive numeric ID`);
  return id;
}

async function curseForgeRequest(fetcher, endpoint, operation, options) {
  let response;
  try {
    response = await fetcher(`${CURSEFORGE}${endpoint}`, {
      ...options, redirect: 'error', signal: AbortSignal.timeout(60000),
    });
  } catch (error) {
    const reason = error?.name === 'TimeoutError' ? 'request timed out' : 'network request failed';
    throw new Error(`${operation}: ${reason}`);
  }
  if (!response.ok) throw new Error(`${operation}: HTTP ${response.status}`);
  try {
    return await response.json();
  } catch {
    throw new Error(`${operation}: invalid JSON response`);
  }
}

export async function uploadRelease(zipPath, version, changelogPath, env = process.env, fetcher = fetch) {
  const project = parseID(env.CURSEFORGE_PROJECT_ID, 'CURSEFORGE_PROJECT_ID');
  const token = env.CF_API_TOKEN?.trim();
  if (!token) throw new Error('Set the CurseForge author token in CF_API_TOKEN');
  const explicitVersion = env.CURSEFORGE_GAME_VERSION_ID
    ? parseID(env.CURSEFORGE_GAME_VERSION_ID, 'CURSEFORGE_GAME_VERSION_ID') : undefined;
  if (typeof version !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9._+-]*$/.test(version)) throw new Error('Invalid release version');
  const [zip, changelog] = await Promise.all([readFile(zipPath), readFile(changelogPath, 'utf8')]);
  if (!/\.zip$/i.test(zipPath) || zip.length < 4 || zip.readUInt32LE(0) !== 0x04034b50) {
    throw new Error('Release file must be a non-empty ZIP archive');
  }
  if (!changelog.trim()) throw new Error('Release changelog is empty');

  const headers = { 'X-Api-Token': token };
  const versions = await curseForgeRequest(fetcher, '/game/versions', 'CurseForge game versions', { headers });
  if (!Array.isArray(versions)) throw new Error('CurseForge game versions: invalid response');
  const matching = versions.filter(entry => entry?.name === GAME_VERSION && isID(entry.id)
    && (explicitVersion === undefined || explicitVersion === entry.id));
  if (matching.length !== 1) {
    throw new Error(`CurseForge version ${GAME_VERSION} could not be resolved uniquely. Check CURSEFORGE_GAME_VERSION_ID.`);
  }

  const body = new FormData();
  body.set('metadata', JSON.stringify({
    changelog, changelogType: 'markdown', displayName: `Forever BiS Tooltip ${version}`,
    gameVersions: [matching[0].id], releaseType: 'release',
  }));
  body.set('file', new Blob([zip], { type: 'application/zip' }), basename(zipPath));
  const result = await curseForgeRequest(fetcher, `/projects/${project}/upload-file`, 'CurseForge upload', {
    method: 'POST', headers, body,
  });
  if (!isID(result?.id)) throw new Error('CurseForge upload: missing file ID in response');
  return result.id;
}

async function main([command, ...args]) {
  if (command === 'compare' && args.length === 2) {
    const [previous, fresh] = await Promise.all(args.map(path => readFile(path, 'utf8')));
    const hash = dataHash(fresh);
    console.log(JSON.stringify({ changed: dataHash(previous) !== hash, hash }));
  } else if (command === 'upload' && args.length === 3) {
    console.log(await uploadRelease(...args));
  } else {
    throw new Error('Usage: release-tools.mjs compare <previous> <fresh> | upload <zip> <version> <changelog>');
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).catch(error => { console.error(error.message); process.exitCode = 1; });
}
