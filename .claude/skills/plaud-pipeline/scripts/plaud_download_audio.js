#!/usr/bin/env node
const fs = require('node:fs');
const path = require('node:path');
const { pipeline } = require('node:stream/promises');

const DEFAULT_API_BASE = 'https://api-apne1.plaud.ai';
const DEFAULT_DOWNLOAD_DIR = 'downloads/plaud';

function parseArgs() {
  const args = process.argv.slice(2);
  const options = {
    folderName: process.env.PLAUD_FOLDER_NAME || '미분류',
    limit: 9999,
    downloadDir: DEFAULT_DOWNLOAD_DIR,
    moveToFolderId: process.env.PLAUD_MOVE_TO_FOLDER_ID || null,
    folderId: process.env.PLAUD_FOLDER_ID || null,
    // Plaud Web URL의 ?categoryId= 값. 기본 'unorganized' = "분류되지 않음" 화면
    categoryId: process.env.PLAUD_CATEGORY_ID !== undefined
        ? process.env.PLAUD_CATEGORY_ID
        : 'unorganized',
    token: process.env.PLAUD_TOKEN || null,
    verbose: false,
    apiBase: process.env.PLAUD_API_BASE || DEFAULT_API_BASE,
  };

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === '--token') options.token = args[++i];
    else if (arg === '--folder-id') options.folderId = args[++i];
    else if (arg === '--folder-name') options.folderName = args[++i];
    else if (arg === '--category-id') options.categoryId = args[++i];
    else if (arg === '--move-to-folder-id') options.moveToFolderId = args[++i];
    else if (arg === '--download-dir') options.downloadDir = args[++i];
    else if (arg === '--limit') options.limit = Number(args[++i]);
    else if (arg === '--api-base') options.apiBase = args[++i];
    else if (arg === '--verbose') options.verbose = true;
  }
  return options;
}

function buildAuthHeaders(token) {
  // 사용자가 LocalStorage에서 'Bearer eyJ...' 형태를 통째로 복사하는 경우 대비
  // — Bearer/공백을 정규화해서 한 번만 prefix
  const cleanToken = String(token).trim().replace(/^[Bb]earer\s+/, '');
  return {
    'accept': 'application/json, text/plain, */*',
    'accept-language': 'ko,en-US;q=0.9,en;q=0.8',
    'app-platform': 'web',
    'authorization': `Bearer ${cleanToken}`,
    'origin': 'https://web.plaud.ai',
    'referer': 'https://web.plaud.ai/',
    'sec-fetch-dest': 'empty',
    'sec-fetch-mode': 'cors',
    'sec-fetch-site': 'same-site',
    'user-agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
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
    if (options.verbose) console.warn(`태그 취득 실패 (${e.message}), 계속 진행합니다...`);
    else console.warn('태그 취득 실패, 계속 진행합니다...');
  }

  const listParams = new URLSearchParams({
    skip: '0',
    limit: String(options.limit),
    is_trash: '0',
    sort_by: 'start_time',
    is_desc: 'true',
  });
  if (options.categoryId) listParams.append('categoryId', options.categoryId);
  if (options.folderId) listParams.append('folderId', options.folderId);

  if (options.verbose) {
    console.log(`목록 요청: ${options.apiBase}/file/simple/web?${listParams}`);
  }

  let listRes = await fetch(`${options.apiBase}/file/simple/web?${listParams}`, { headers });
  if (!listRes.ok) {
    const bodyPreview = (await listRes.text().catch(() => '')).slice(0, 300);
    if (options.verbose) {
      console.error(`응답 ${listRes.status} ${listRes.statusText}`);
      console.error(`응답 본문 (첫 300자): ${bodyPreview}`);
      console.error('힌트: 401이면 토큰이 만료/무효이거나, API base가 다른 region입니다.');
      console.error('  - PLAUD_API_BASE=https://api.plaud.ai 시도');
      console.error('  - 또는 Plaud Web에서 새 토큰 복사');
    }
    throw new Error(`목록 취득 실패: ${listRes.status} ${listRes.statusText}`);
  }

  let listData = await listRes.json();

  // 서버가 region mismatch를 알려주면 (status=-302 + data.domains.api) 자동으로 재시도
  if (listData && listData.status === -302 && listData.data && listData.data.domains && listData.data.domains.api) {
    const correctBase = listData.data.domains.api.replace(/\/$/, '');
    console.warn(`서버 안내: region mismatch — API base를 ${correctBase} 로 자동 전환`);
    options.apiBase = correctBase;
    listRes = await fetch(`${correctBase}/file/simple/web?${listParams}`, { headers });
    if (!listRes.ok) {
      throw new Error(`재시도 후에도 실패: ${listRes.status} ${listRes.statusText}`);
    }
    listData = await listRes.json();
    console.warn(`💡 .env 에 다음을 추가/수정하면 다음 실행부터 한 번에 처리됩니다:`);
    console.warn(`    PLAUD_API_BASE=${correctBase}`);
  }

  const allFiles = listData.data_file_list || [];

  // "미분류"의 다국어/UI 라벨 변형 — 태그가 없는 파일을 가리킴
  const UNTAGGED_ALIASES = new Set([
    '미분류',
    '분류되지 않음',
    'Uncategorized',
    'untagged',
    '',
  ]);

  const fileToTag = (f) => {
    const tagId = (f.filetag_id_list && f.filetag_id_list[0]) ? f.filetag_id_list[0] : null;
    const tagName = tagId ? (tagMap[tagId] || `<unknown:${tagId}>`) : null;
    return { tagId, tagName };
  };

  const targetFiles = allFiles.filter(f => {
    const { tagId, tagName } = fileToTag(f);
    if (options.folderId) {
      return tagId === options.folderId;
    }
    if (UNTAGGED_ALIASES.has(options.folderName)) {
      // 미분류 동의어 — 태그가 없는 파일
      return tagId === null;
    }
    return tagName === options.folderName;
  });

  console.log(`"${options.folderName}"에서 ${targetFiles.length}개 파일 발견. (서버 전체: ${allFiles.length}개)`);

  // 서버 자체가 0개인 경우 — region/토큰 문제 가능성
  if (allFiles.length === 0) {
    console.warn(`서버에서 받은 파일 목록이 빈 배열입니다. 가능한 원인:`);
    console.warn(`  1) PLAUD_API_BASE 가 잘못된 region`);
    console.warn(`     - 현재: ${options.apiBase}`);
    console.warn(`     - 토큰의 region에 맞춰 시도: https://api-apne1.plaud.ai (한국/일본)`);
    console.warn(`     - 또는: https://api.plaud.ai (글로벌)`);
    console.warn(`  2) 토큰이 발급된 계정과 다른 region`);
    console.warn(`  3) Plaud Web 새로고침 → "분류되지 않음" 폴더에 파일이 실제로 보이는지 확인`);
    if (options.verbose) {
      console.warn(`  응답 키: ${Object.keys(listData).join(', ')}`);
      console.warn(`  응답 첫 200자: ${JSON.stringify(listData).slice(0, 200)}`);
    }
  }

  // 매칭 실패 시 사용 가능한 폴더 분포 출력 (사용자 디버깅 도움)
  if (targetFiles.length === 0 && allFiles.length > 0) {
    const tagSummary = {};
    allFiles.forEach(f => {
      const { tagId } = fileToTag(f);
      const key = tagId
        ? (tagMap[tagId] || `<unknown tagId:${tagId}>`)
        : '<태그없음 (미분류/분류되지 않음/Uncategorized)>';
      tagSummary[key] = (tagSummary[key] || 0) + 1;
    });
    console.warn(`전체 ${allFiles.length}개 파일이 있지만 "${options.folderName}"에 매칭된 파일은 0개입니다.`);
    console.warn(`현재 발견된 폴더 분포:`);
    for (const [name, count] of Object.entries(tagSummary)) {
      console.warn(`  - ${name}: ${count}개`);
    }
    console.warn(`해결: .env 에 PLAUD_FOLDER_NAME=<위 목록 중 하나> 추가, 또는 PLAUD_FOLDER_ID=<태그 ID>`);
  }

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
