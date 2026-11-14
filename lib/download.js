import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';

export const REPO_OWNER = 'Ice0828';
export const REPO_NAME = 'magpie-agent-cursor-bridge-linux';

/**
 * Identify platform, architecture and corresponding release asset names.
 */
export function getPlatformBinaryInfo() {
  const isWin = process.platform === 'win32';
  const isLinux = process.platform === 'linux';
  const isDarwin = process.platform === 'darwin';
  const arch = process.arch;

  let platformName = '';
  if (isLinux) platformName = 'linux';
  else if (isDarwin) platformName = 'darwin';
  else if (isWin) platformName = 'windows';
  else platformName = process.platform;

  const binName = isWin ? 'cursor-magpie-bridge.exe' : 'cursor-magpie-bridge';
  const assetName = isWin
    ? `cursor-magpie-bridge-${platformName}-${arch}.exe`
    : `cursor-magpie-bridge-${platformName}-${arch}`;

  const platformKey = isWin
    ? 'engine_win32_x64'
    : isLinux
      ? `engine_linux_${arch}`
      : `engine_darwin_${arch}`;

  return { binName, assetName, platformKey, arch, platform: process.platform };
}

/**
 * Compute SHA-256 hash of a file.
 */
export function computeSha256(filePath) {
  const hash = createHash('sha256');
  const buffer = fs.readFileSync(filePath);
  hash.update(buffer);
  return hash.digest('hex');
}

/**
 * Generate candidate download URLs (direct GitHub Release + fast mirrors).
 */
export function getCandidateUrls(version, assetName) {
  const direct = `https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download/v${version}/${assetName}`;
  const candidates = [];

  if (process.env.CURSOR_BRIDGE_DOWNLOAD_URL) {
    candidates.push(process.env.CURSOR_BRIDGE_DOWNLOAD_URL);
  }

  // Direct GitHub Release URL
  candidates.push(direct);

  // Community fast mirrors (for mainland China environments)
  candidates.push(`https://ghfast.top/${direct}`);
  candidates.push(`https://ghproxy.net/${direct}`);

  return candidates;
}

/**
 * Fetch and parse release SHA256SUMS if available.
 * Candidate mirrors (ghfast.top, ghproxy.net) are queried in sequence.
 */
export async function fetchReleaseSha256(version, assetName, { log = console.log } = {}) {
  const checksumUrls = getCandidateUrls(version, 'SHA256SUMS');
  for (const url of checksumUrls) {
    try {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 8000);
      const res = await fetch(url, { redirect: 'follow', signal: controller.signal });
      clearTimeout(timer);
      if (!res.ok) continue;
      const text = await res.text();
      for (const line of text.split('\n')) {
        const parts = line.trim().split(/\s+/);
        if (parts.length >= 2) {
          const hash = parts[0].toLowerCase();
          const filename = parts[1].replace(/^\*/, '');
          if (filename === assetName || path.basename(filename) === assetName) {
            return hash;
          }
        }
      }
    } catch {}
  }
  return null;
}

/**
 * Ensure the native engine binary is present and valid.
 * Downloads from GitHub Releases if missing or corrupted.
 */
export async function ensureBinary(source, { log = console.log } = {}) {
  const info = getPlatformBinaryInfo();
  const binDir = path.join(source, 'bin');
  fs.mkdirSync(binDir, { recursive: true, mode: 0o755 });
  const targetPath = path.join(binDir, info.binName);

  const manifest = JSON.parse(fs.readFileSync(path.join(source, 'package.json'), 'utf8'));
  const version = manifest.version;
  const checksumFile = path.join(source, 'integrity.json');
  let fallbackDigest = null;

  if (fs.existsSync(checksumFile)) {
    try {
      const checksums = JSON.parse(fs.readFileSync(checksumFile, 'utf8'));
      fallbackDigest = checksums[info.platformKey] || checksums.engine;
    } catch {}
  }

  // 1. If binary already exists and matches static fallback digest, reuse immediately
  if (fs.existsSync(targetPath) && fallbackDigest) {
    const currentDigest = computeSha256(targetPath);
    if (currentDigest === fallbackDigest) {
      return targetPath;
    }
  }

  // 2. Resolve authoritative release digest from SHA256SUMS with static integrity.json fallback
  let expectedDigest = fallbackDigest;
  try {
    const remoteDigest = await fetchReleaseSha256(version, info.assetName, { log });
    if (remoteDigest) {
      expectedDigest = remoteDigest;
      // Refresh local integrity cache when authoritative digest is fetched
      if (fs.existsSync(checksumFile)) {
        try {
          const checksums = JSON.parse(fs.readFileSync(checksumFile, 'utf8'));
          if (checksums[info.platformKey] !== remoteDigest) {
            checksums[info.platformKey] = remoteDigest;
            checksums.engine = remoteDigest;
            fs.writeFileSync(checksumFile, JSON.stringify(checksums, null, 2) + '\n');
          }
        } catch {}
      }
    }
  } catch {}

  // If local binary exists and matches resolved expected digest, reuse
  if (fs.existsSync(targetPath)) {
    if (!expectedDigest) {
      return targetPath;
    }
    const currentDigest = computeSha256(targetPath);
    if (currentDigest === expectedDigest) {
      return targetPath;
    }
    log(`[cursor-bridge] 本地引擎哈希不匹配 (${currentDigest.slice(0, 8)}... != ${expectedDigest.slice(0, 8)}...)，将重新下载最新发布版本...`);
  }

  // 2. Download from release assets
  log(`[cursor-bridge] 正在获取原生引擎 v${version} (${info.assetName})...`);
  const urls = getCandidateUrls(version, info.assetName);
  let lastError = null;

  for (const url of urls) {
    const tmpPath = path.join(binDir, `${info.binName}.${Date.now()}.tmp`);
    try {
      log(`[cursor-bridge] 正在尝试下载: ${url}`);
      const controller = new AbortController();
      const timeoutMs = Number(process.env.CURSOR_BRIDGE_DOWNLOAD_TIMEOUT_MS) || 60000;
      const timer = setTimeout(() => controller.abort(), timeoutMs);

      const res = await fetch(url, { redirect: 'follow', signal: controller.signal });
      clearTimeout(timer);

      if (!res.ok) {
        throw new Error(`HTTP ${res.status} ${res.statusText}`);
      }

      const fileStream = fs.createWriteStream(tmpPath);
      await pipeline(Readable.fromWeb(res.body), fileStream);

      // Verify checksum
      const downloadedDigest = computeSha256(tmpPath);
      if (expectedDigest && downloadedDigest !== expectedDigest) {
        try { fs.unlinkSync(tmpPath); } catch {}
        throw new Error(`校验和不匹配: 期望 ${expectedDigest}, 实际 ${downloadedDigest}`);
      }

      fs.chmodSync(tmpPath, 0o755);
      fs.renameSync(tmpPath, targetPath);
      const sizeMb = (fs.statSync(targetPath).size / 1024 / 1024).toFixed(1);
      log(`[cursor-bridge] 原生引擎下载并校验成功 (${sizeMb} MB)。`);
      return targetPath;
    } catch (err) {
      try { if (fs.existsSync(tmpPath)) fs.unlinkSync(tmpPath); } catch {}
      lastError = err;
      log(`[cursor-bridge] 该镜像下载未完成 (${err.message})，尝试备用地址...`);
    }
  }

  throw new Error(`无法下载原生引擎二进制: ${lastError?.message || '全部下载源均失败'}。请检查网络连接或手动执行 scripts/build-native.sh 编译。`);
}
