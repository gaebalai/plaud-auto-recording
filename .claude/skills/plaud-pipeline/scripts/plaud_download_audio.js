#!/usr/bin/env node
const fs = require('node:fs');
const path = require('node:path');
const { pipeline } = require('node:stream/promises');

const DEFAULT_API_BASE = 'https://api-apne1.plaud.ai';
const DEFAULT_DOWNLOAD_DIR = 'downloads/plaud';

function parseArgs() {
  const args = process.argv.slice(2);
  const options = {
    folderName: '미분류',
    limit: 9999,
    downloadDir: DEFAULT_DOWNLOAD_DIR,
    moveToFolderId: process.env.PLAUD_MOVE_TO_FOLDER_ID || null,
    folderId: null,
    token: process.env.PLAUD_TOKEN || null,
    verbose: false,
    apiBase: process.env.PLAUD_API_BASE || DEFAULT_API_BASE,
  };

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === '--token') options.token = args[++i];
    else if (arg === '--folder-id') options.folderId = args[++i];
    else if (arg === '--folder-name') options.folderName = args[++i];
    else if (arg === '--move-to-folder-id') options.moveToFolderId = args[++i];
    else if (arg === '--download-dir') options.downloadDir = args[++i];
    else if (arg === '--limit') options.limit = Number(args[++i]);
    else if (arg === '--api-base') options.apiBase = args[++i];
    else if (arg === '--verbose') options.verbose = true;
  }
  return options;
}

function buildAuthHeaders(token) {
  return {
    'accept': 'application/json, text/plain, */*',
    'app-platform': 'web',
    'authorization': token.startsWith('Bearer ') ? token : `Bearer ${token}`,
    'origin': 'https://web.plaud.ai',
    'referer': 'https://web.plaud.ai/',
  };
}

function toSafeFilename(str) {
  return str.replace(/[\\/:*?"<>|]/g, '_').trim();
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function withRetry(fn, label, retries = 1, delayMs = 2000) {
  let lastErr;
  for (let i = 0; i <= retries; i++) {
    try {
      return await fn();
    } catch (err) {
      lastErr = err;
      if (i < retries) {
        console.warn(`${label} 재시도 (${i + 1}/${retries}): ${err.message}`);
        await sleep(delayMs);
      }
    }
  }
  throw lastErr;
}

async function downloadOne(file, headers, options) {
  const fileId = file.fileId || file.id;
  const fileName = toSafeFilename(file.filename || file.title || `audio_${fileId}`);

  const urlRes = await fetch(`${options.apiBase}/file/temp-url/${fileId}`, { headers });
  if (!urlRes.ok) throw new Error(`temp-url 응답 ${urlRes.status}`);

  const urlData = await urlRes.json();
  const downloadUrl = urlData.data?.temp_url || urlData.temp_url;
  if (!downloadUrl) throw new Error('temp_url 없음');

  const ext = path.extname(new URL(downloadUrl).pathname) || '.mp3';
  const destPath = path.join(options.downloadDir, `${fileName}${ext}`);

  const fileRes = await fetch(downloadUrl);
  if (!fileRes.ok || !fileRes.body) throw new Error(`다운로드 응답 ${fileRes.status}`);

  await pipeline(fileRes.body, fs.createWriteStream(destPath));
  return { fileName, ext, fileId, destPath };
}

async function main() {
  const options = parseArgs();
  if (!options.token) {
    console.error('토큰이 없습니다.');
    process.exit(1);
  }

  if (!fs.existsSync(options.downloadDir)) {
    fs.mkdirSync(options.downloadDir, { recursive: true });
  }

  const headers = buildAuthHeaders(options.token);

  if (options.verbose) console.log(`API Base: ${options.apiBase}`);

  let tagMap = {};
  try {
    const tagRes = await fetch(`${options.apiBase}/filetag/`, { headers });
    const tagData = await tagRes.json();
    if (tagData.data_filetag_list) {
      tagData.data_filetag_list.forEach(t => (tagMap[t.id] = t.name));
    }
  } catch (e) {
    console.warn('태그 취득 실패, 계속 진행합니다...');
  }

  const listParams = new URLSearchParams({
    skip: '0',
    limit: String(options.limit),
    is_trash: '0',
    sort_by: 'start_time',
    is_desc: 'true',
  });
  if (options.folderId) listParams.append('folderId', options.folderId);

  const listRes = await fetch(`${options.apiBase}/file/simple/web?${listParams}`, { headers });
  if (!listRes.ok) throw new Error(`목록 취득 실패: ${listRes.status}`);

  const listData = await listRes.json();
  const allFiles = listData.data_file_list || [];

  const targetFiles = allFiles.filter(f => {
    const tagId = (f.filetag_id_list && f.filetag_id_list[0]) ? f.filetag_id_list[0] : null;
    const tagName = tagId ? tagMap[tagId] : '미분류';
    return tagName === options.folderName;
  });

  console.log(`"${options.folderName}"에서 ${targetFiles.length}개 파일 발견.`);

  let okCount = 0;
  let failCount = 0;

  for (const file of targetFiles) {
    const fallbackId = file.fileId || file.id;
    const displayName = toSafeFilename(file.filename || file.title || `audio_${fallbackId}`);

    try {
      const result = await withRetry(
        () => downloadOne(file, headers, options),
        `다운로드 ${displayName}`,
        1,
        2000
      );
      okCount++;
      console.log(`다운로드 완료: ${result.fileName}${result.ext}`);

      if (options.moveToFolderId) {
        try {
          const moveRes = await withRetry(
            () => fetch(`${options.apiBase}/file/update-tags`, {
              method: 'POST',
              headers: { ...headers, 'content-type': 'application/json' },
              body: JSON.stringify({ file_id_list: [result.fileId], filetag_id: options.moveToFolderId }),
            }),
            `폴더 이동 ${displayName}`,
            1,
            1000
          );
          if (moveRes.ok) console.log(`  -> 폴더 이동 완료: ${options.moveToFolderId}`);
          else console.warn(`  -> 폴더 이동 응답 ${moveRes.status}`);
        } catch (moveErr) {
          console.warn(`  -> 폴더 이동 실패: ${moveErr.message}`);
        }
      }
    } catch (err) {
      console.error(`${displayName} 처리 실패: ${err.message}`);
      failCount++;
    }
  }

  console.log(`완료: 성공 ${okCount} / 실패 ${failCount}`);
  if (failCount > 0) process.exitCode = 2;
}

main().catch(e => {
  console.error(e);
  process.exit(1);
});
