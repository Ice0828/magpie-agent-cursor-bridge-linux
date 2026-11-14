import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  getPlatformBinaryInfo,
  computeSha256,
  getCandidateUrls,
  ensureBinary
} from '../lib/download.js';

const source = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

test('getPlatformBinaryInfo reports valid platform and asset structure', () => {
  const info = getPlatformBinaryInfo();
  assert.equal(typeof info.binName, 'string');
  assert.equal(typeof info.assetName, 'string');
  assert.equal(typeof info.platformKey, 'string');
  assert.match(info.assetName, /cursor-magpie-bridge/);
  if (process.platform === 'linux') {
    assert.match(info.assetName, /linux/);
    assert.equal(info.binName, 'cursor-magpie-bridge');
  }
});

test('getCandidateUrls includes GitHub release URL and fast mirrors', () => {
  const urls = getCandidateUrls('0.3.1', 'cursor-magpie-bridge-linux-x64');
  assert.ok(urls.length >= 3);
  assert.ok(urls[0].includes('github.com/Ice0828/magpie-agent-cursor-bridge-linux/releases/download/v0.3.1'));
  assert.ok(urls.some(u => u.includes('ghfast.top')));
  assert.ok(urls.some(u => u.includes('ghproxy.net')));
});

test('computeSha256 calculates accurate digest for existing files', () => {
  const pkgJson = path.join(source, 'package.json');
  const digest = computeSha256(pkgJson);
  assert.match(digest, /^[a-f0-9]{64}$/);
});

test('ensureBinary reuses existing valid binary without network calls', async () => {
  const logs = [];
  const target = await ensureBinary(source, { log: (msg) => logs.push(msg) });
  assert.ok(fs.existsSync(target));
  // Since binary already exists and matches integrity.json, no download log should appear
  assert.equal(logs.filter(m => m.includes('正在尝试下载')).length, 0);
});
