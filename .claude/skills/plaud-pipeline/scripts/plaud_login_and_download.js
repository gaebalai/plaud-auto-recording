#!/usr/bin/env node
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { chromium } = require('playwright');

const DEFAULT_LOGIN_URL = 'https://web.plaud.ai/login';
const LOGIN_TIMEOUT = 60000;

function parseArgs() {
  const args = process.argv.slice(2);
  const options = {
    email: process.env.PLAUD_EMAIL || '',
    password: process.env.PLAUD_PASSWORD || '',
    folderName: '미분류',
    folderId: null,
    moveToFolderId: process.env.PLAUD_MOVE_TO_FOLDER_ID || null,
    downloadDir: null,
    limit: 9999,
    apiBase: process.env.PLAUD_API_BASE || null,
    headless: false,
    download: true,
    verbose: false,
  };

  for (let i = 0; i < args.length; i++) {
    const token = args[i];
    switch (token) {
      case '--email': options.email = args[++i] || options.email; break;
      case '--password': options.password = args[++i] || options.password; break;
      case '--folder-name': options.folderName = args[++i] || options.folderName; break;
      case '--folder-id': options.folderId = args[++i] || options.folderId; break;
      case '--move-to-folder-id': options.moveToFolderId = args[++i] || options.moveToFolderId; break;
      case '--download-dir': options.downloadDir = args[++i] || options.downloadDir; break;
      case '--limit': options.limit = Number(args[++i]) || options.limit; break;
      case '--api-base': options.apiBase = args[++i] || options.apiBase; break;
      case '--headless': options.headless = true; break;
      case '--no-download': options.download = false; break;
      case '--verbose': options.verbose = true; break;
    }
  }

  return options;
}

async function main() {
  const options = parseArgs();

  if (!options.email || !options.password) {
    console.error('PLAUD_EMAIL / PLAUD_PASSWORD를 .env 또는 인수로 제공하세요.');
    process.exit(1);
  }

  const token = await loginAndExtractToken(options);
  console.log(`Token acquired: ${token.slice(0, 12)}...`);

  if (!options.download) return;

  const scriptPath = path.join(__dirname, 'plaud_download_audio.js');
  const args = [scriptPath, '--token', token];

  if (options.folderId) {
    args.push('--folder-id', options.folderId);
  } else {
    args.push('--folder-name', options.folderName);
  }

  if (options.moveToFolderId) {
    args.push('--move-to-folder-id', options.moveToFolderId);
  }

  if (options.downloadDir) {
    args.push('--download-dir', options.downloadDir);
  }

  if (options.limit) {
    args.push('--limit', String(options.limit));
  }

  if (options.apiBase) {
    args.push('--api-base', options.apiBase);
  }

  if (options.verbose) {
    args.push('--verbose');
  }

  const result = spawnSync(process.execPath, args, { stdio: 'inherit' });
  if (result.status !== 0) {
    throw new Error('plaud_download_audio.js 실패');
  }
}

async function loginAndExtractToken({ email, password, headless }) {
  const browser = await chromium.launch({ headless });
  const context = await browser.newContext({ viewport: { width: 1366, height: 768 } });
  const page = await context.newPage();

  try {
    await page.goto(DEFAULT_LOGIN_URL, { waitUntil: 'networkidle', timeout: LOGIN_TIMEOUT });

    const emailSelectors = [
      'input[placeholder="이메일 주소"]',
      'input[placeholder="Email"]',
      'input[type="email"]',
      'input[name="email"]',
    ];
    const passwordSelectors = [
      'input[placeholder="비밀번호"]',
      'input[placeholder="Password"]',
      'input[type="password"]',
      'input[name="password"]',
    ];

    let emailFilled = false;
    for (const sel of emailSelectors) {
      try { await page.fill(sel, email, { timeout: 3000 }); emailFilled = true; break; } catch (_) {}
    }
    if (!emailFilled) throw new Error('이메일 입력란을 찾지 못했습니다');

    let passwordFilled = false;
    for (const sel of passwordSelectors) {
      try { await page.fill(sel, password, { timeout: 3000 }); passwordFilled = true; break; } catch (_) {}
    }
    if (!passwordFilled) throw new Error('비밀번호 입력란을 찾지 못했습니다');

    await page.click('button:has-text("로그인"), button:has-text("Login"), button[type="submit"]');

    await page.waitForFunction(() => {
      const keys = ['tokenstr', 'token', 'access_token', 'plaud_token', 'auth_token'];
      const storages = [window.localStorage, window.sessionStorage];
      for (const storage of storages) {
        if (!storage) continue;
        for (const key of keys) {
          const value = storage.getItem(key);
          if (value && value.trim()) return true;
        }
      }
      return false;
    }, { timeout: LOGIN_TIMEOUT });

    const token = await page.evaluate(() => {
      const keys = ['tokenstr', 'token', 'access_token', 'plaud_token', 'auth_token'];
      const storages = [window.localStorage, window.sessionStorage];
      for (const storage of storages) {
        if (!storage) continue;
        for (const key of keys) {
          const value = storage.getItem(key);
          if (value && value.trim()) return value;
        }
      }
      return null;
    });

    if (!token) throw new Error('토큰을 찾을 수 없습니다');
    return token;
  } finally {
    await browser.close();
  }
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
