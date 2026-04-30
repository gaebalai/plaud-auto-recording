#!/usr/bin/env node
// 구글 간편로그인 사용 시 토큰 취득용.
// 처음에 한 번 GUI에서 직접 구글 로그인하면 프로필이 디스크에 저장되고,
// 이후 자동 실행에서는 살아있는 세션을 재사용해 토큰만 stdout으로 출력한다.
//
// 사용법:
//   첫 실행 (브라우저 떠서 직접 구글 로그인):
//     node plaud_session_login.js --first-time
//
//   이후 자동 실행 (cron 등):
//     node plaud_session_login.js --headless --token-only
//
// 출력:
//   - stdout: 토큰 문자열 (성공 시)
//   - stderr: 안내·오류 메시지

const path = require('node:path');
const os = require('node:os');
const fs = require('node:fs');
const { chromium } = require('playwright');

const TOKEN_KEYS = ['tokenstr', 'token', 'access_token', 'plaud_token', 'auth_token'];
const PLAUD_URL = 'https://web.plaud.ai/';

function parseArgs() {
  const args = process.argv.slice(2);
  const options = {
    profileDir:
      process.env.PLAUD_PROFILE_DIR ||
      path.join(os.homedir(), '.plaud-pipeline-profile'),
    firstTime: false,
    headless: process.env.PLAUD_HEADLESS === '1',
    timeoutMs: 300000,
    tokenOnly: false,
  };
  for (let i = 0; i < args.length; i++) {
    const t = args[i];
    if (t === '--profile-dir') options.profileDir = args[++i];
    else if (t === '--first-time') {
      options.firstTime = true;
      options.headless = false;
    } else if (t === '--headless') options.headless = true;
    else if (t === '--timeout') options.timeoutMs = Number(args[++i]) * 1000;
    else if (t === '--token-only') options.tokenOnly = true;
  }
  return options;
}

async function readToken(page) {
  return await page.evaluate((keys) => {
    for (const storage of [window.localStorage, window.sessionStorage]) {
      if (!storage) continue;
      for (const key of keys) {
        const v = storage.getItem(key);
        if (v && v.trim()) return v;
      }
    }
    return null;
  }, TOKEN_KEYS);
}

async function main() {
  const opts = parseArgs();
  fs.mkdirSync(opts.profileDir, { recursive: true });

  if (!opts.tokenOnly) {
    console.error(`Profile: ${opts.profileDir}`);
    console.error(`Headless: ${opts.headless}`);
  }

  const context = await chromium.launchPersistentContext(opts.profileDir, {
    headless: opts.headless,
    viewport: { width: 1366, height: 768 },
  });

  const page = context.pages()[0] || (await context.newPage());

  try {
    await page.goto(PLAUD_URL, { waitUntil: 'networkidle', timeout: 60000 });

    let token = await readToken(page);
    if (token) {
      if (!opts.tokenOnly) console.error('기존 세션에서 토큰을 찾았습니다.');
      console.log(token);
      return;
    }

    if (opts.headless) {
      throw new Error(
        '세션이 없거나 만료되었습니다. ' +
          '다음 명령으로 GUI에서 한 번 구글 로그인을 해주세요:\n' +
          '  node plaud_session_login.js --first-time'
      );
    }

    console.error('====================================================');
    console.error('떠 있는 브라우저에서 "Google로 로그인"을 눌러');
    console.error('직접 구글 로그인을 완료해 주세요.');
    console.error('로그인 후 자동으로 토큰을 추출하고 종료합니다.');
    console.error(`타임아웃: ${opts.timeoutMs / 1000}초`);
    console.error('====================================================');

    await page.waitForFunction(
      (keys) => {
        for (const storage of [window.localStorage, window.sessionStorage]) {
          if (!storage) continue;
          for (const key of keys) {
            const v = storage.getItem(key);
            if (v && v.trim()) return true;
          }
        }
        return false;
      },
      TOKEN_KEYS,
      { timeout: opts.timeoutMs }
    );

    token = await readToken(page);
    if (!token) throw new Error('토큰을 찾을 수 없습니다');

    if (!opts.tokenOnly) console.error('토큰 취득 완료. 세션이 프로필에 저장되었습니다.');
    console.log(token);
  } finally {
    await context.close();
  }
}

main().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
