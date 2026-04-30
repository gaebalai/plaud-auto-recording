#!/usr/bin/env node
// create-plaud-pipeline
// PLAUD NotePin 자동 녹음 파이프라인 부트스트랩 CLI
//
// Usage:
//   npx create-plaud-pipeline <target-dir> [options]
//   npm create plaud-pipeline <target-dir> [options]
//
// Options:
//   --auto         setup.sh --yes 를 자동 실행 (확인 없음)
//   --no-setup     repo 복제만 하고 setup.sh는 실행하지 않음
//   --branch <b>   기본 main 외의 브랜치 사용
//   -h, --help

const { execSync, spawnSync } = require('node:child_process');
const path = require('node:path');
const fs = require('node:fs');

const REPO = process.env.PLAUD_REPO || 'gaebalai/plaud-auto-recording';
const DEFAULT_BRANCH = process.env.PLAUD_BRANCH || 'main';

const colors = process.stdout.isTTY
  ? {
      green: (s) => `\x1b[32m${s}\x1b[0m`,
      yellow: (s) => `\x1b[33m${s}\x1b[0m`,
      red: (s) => `\x1b[31m${s}\x1b[0m`,
      blue: (s) => `\x1b[34m${s}\x1b[0m`,
      bold: (s) => `\x1b[1m${s}\x1b[0m`,
    }
  : { green: (s) => s, yellow: (s) => s, red: (s) => s, blue: (s) => s, bold: (s) => s };

function log(prefix, message) {
  console.log(`${prefix} ${message}`);
}
const ok = (m) => log(colors.green('✓'), m);
const info = (m) => log(colors.blue('▸'), m);
const warn = (m) => log(colors.yellow('⚠'), m);
const err = (m) => console.error(`${colors.red('✗')} ${m}`);

function printHelp() {
  console.log(`
create-plaud-pipeline — PLAUD 자동 녹음 파이프라인 부트스트랩

사용법:
  npx create-plaud-pipeline <디렉토리> [옵션]
  npm create plaud-pipeline <디렉토리> [옵션]

옵션:
  --auto         setup.sh --yes 자동 실행
  --no-setup     repo 복제만, setup.sh는 직접
  --branch <b>   기본 main 외 브랜치
  -h, --help     이 도움말

환경변수:
  PLAUD_REPO     repo override (기본: ${REPO})
  PLAUD_BRANCH   브랜치 override (기본: ${DEFAULT_BRANCH})

예시:
  npx create-plaud-pipeline my-recording
  npx create-plaud-pipeline my-recording --auto
  PLAUD_BRANCH=dev npx create-plaud-pipeline my-recording
`);
}

function parseArgs(argv) {
  const args = argv.slice(2);
  const out = {
    target: null,
    auto: false,
    skipSetup: false,
    branch: DEFAULT_BRANCH,
    help: false,
  };
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '-h' || a === '--help') out.help = true;
    else if (a === '--auto') out.auto = true;
    else if (a === '--no-setup') out.skipSetup = true;
    else if (a === '--branch') out.branch = args[++i] || out.branch;
    else if (!a.startsWith('-') && !out.target) out.target = a;
  }
  return out;
}

function preflight() {
  if (process.platform !== 'darwin') {
    err(`이 프로젝트는 macOS 전용입니다. (현재: ${process.platform})`);
    process.exit(1);
  }
  const nodeMajor = parseInt(process.versions.node.split('.')[0], 10);
  if (nodeMajor < 18) {
    err(`Node.js 18 이상이 필요합니다. (현재: ${process.versions.node})`);
    process.exit(1);
  }
}

function ensureFreshTarget(target) {
  if (fs.existsSync(target)) {
    err(`${target} 이 이미 존재합니다.`);
    info('다른 이름을 인수로 주세요.');
    process.exit(1);
  }
}

function clone(repo, branch, target) {
  info(`${repo}#${branch} → ${target} 복제 중...`);
  const result = spawnSync('npx', ['--yes', 'tiged', `${repo}#${branch}`, target], {
    stdio: 'inherit',
  });
  if (result.status !== 0) {
    err('복제 실패. repo 이름과 브랜치를 확인하세요.');
    process.exit(result.status || 1);
  }
  ok('복제 완료');
}

function makeExecutable(target) {
  const candidates = [
    'setup.sh',
    'register_cron.sh',
    'bootstrap.sh',
    '.claude/skills/plaud-pipeline/scripts/run_pipeline.sh',
    '.claude/skills/plaud-pipeline/scripts/health_check.sh',
    '.claude/skills/plaud-pipeline/scripts/plaud_login_and_download.js',
    '.claude/skills/plaud-pipeline/scripts/plaud_session_login.js',
    '.claude/skills/plaud-pipeline/scripts/plaud_download_audio.js',
    '.claude/skills/plaud-pipeline/scripts/whisper_transcribe.py',
  ];
  for (const rel of candidates) {
    const abs = path.join(target, rel);
    try {
      if (fs.existsSync(abs)) fs.chmodSync(abs, 0o755);
    } catch (_) {}
  }
}

function runSetup(target, auto) {
  const args = auto ? ['setup.sh', '--yes'] : ['setup.sh'];
  info(`./setup.sh${auto ? ' --yes' : ''} 실행 중...`);
  const result = spawnSync('bash', args, { cwd: target, stdio: 'inherit' });
  if (result.status !== 0) {
    err(`setup.sh 종료 코드: ${result.status}`);
    process.exit(result.status || 1);
  }
}

function printPrologue() {
  console.log('');
  console.log('======================================================');
  console.log('  PLAUD 자동 녹음 파이프라인 설치');
  console.log('======================================================');
  console.log('');
  console.log('  설치 도중 Plaud 인증 정보를 묻습니다.');
  console.log('  의존성 설치(5~10분) 동안 미리 토큰을 받아두면 빠릅니다:');
  console.log('');
  console.log('    1) 본인 Chrome에서 https://web.plaud.ai 로그인');
  console.log('    2) ⌘⌥I (개발자도구) → Application → Local Storage');
  console.log('    3) tokenstr 값 복사 (eyJhbGc... 200~400자)');
  console.log('');
  console.log('  (Plaud에 비밀번호 설정 가능하면 password 모드도 OK)');
  console.log('');
  console.log('======================================================');
  console.log('');
}

function printNextSteps(target) {
  console.log('');
  ok('부트스트랩 완료');
  console.log('');
  info('다음 단계:');
  console.log(`  cd ${target}`);
  console.log('  npm run pipeline       # 시험 실행');
  console.log('  npm run register-cron  # cron 자동 등록 (매일 03:00)');
  console.log('');
  console.log('  자세한 시나리오: SCENARIOS.md');
  console.log('  인증이 막히면: setup.sh 재실행 → 옵션 2 (token 모드)');
}

function main() {
  const opts = parseArgs(process.argv);

  if (opts.help) {
    printHelp();
    return;
  }

  if (!opts.target) {
    err('대상 디렉토리를 지정해 주세요.');
    info('예: npx create-plaud-pipeline my-recording');
    process.exit(1);
  }

  preflight();
  ensureFreshTarget(opts.target);
  clone(REPO, opts.branch, opts.target);
  makeExecutable(opts.target);

  if (opts.skipSetup) {
    console.log('');
    info(`다음 단계:\n  cd ${opts.target}\n  ./setup.sh`);
    return;
  }

  printPrologue();
  runSetup(opts.target, opts.auto);
  printNextSteps(opts.target);
}

try {
  main();
} catch (e) {
  err(e.message || String(e));
  process.exit(1);
}
