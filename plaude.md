# PLAUD 녹음 자동화 완전 가이드 - Whisper 로컬 음성인식 + Obsidian, OpenClaw 자동 저장 파이프라인 구축


PLAUD NotePin은 흔히 "AI가 알아서 요약해 주는 녹음기"로 소개된다. 작고, 가볍고, 시작도 빠르다. Wi-Fi 환경에서 충전해 두면 클라우드 동기화까지 알아서 진행된다. 녹음의 입구로서는 꽤 잘 만들어진 기기다.

하지만 생활 로그 용도로 본격적으로 돌리기 시작하면, 정작 원하게 되는 건 AI 요약 그 자체가 아니다. 진짜 필요한 건, 사람이 따로 신경 쓰지 않아도 녹음이 자동으로 수집되고, 텍스트가 되고, 나중에 읽을 수 있는 형태로 남는 것이다.

​

앱을 매번 열어서 확인하고, 필요하면 내보내고, 나중에 정리하다보면 기기를 안쓰게 되어버리고 당근하게 된다. PLAUD 제품이 멋지지만 막상 가장 필요한 것은 매일 데이터가 제대로 쌓이는 파이프라인이라고 생각했다.

​

이 글에서는 실제로 운영 중인 구성을 바탕으로, 완전 자동으로 PLAUD 녹음을 Plaud Web에서 수집하고 → 로컬 Whisper로 음성 인식하고 → Obsidian Vault에 저장하는 데까지 정리한다. 물론 겉다리로 OpenClaw와의 연결 방법도 살짝 다루지만, 메인은 아니기 때문에, OpenClaw 없이도 이 구성 자체는 완전히 성립한다.

​

이번에 구현해본 것은, (본인의 귀차니즘을 해결하기 위해 구현한 것이라는 것을 참고하고 읽어주세요)

PLAUD NotePin
    → Plaud Web 자동 업로드
    → 자동 수집 스크립트 (Node.js + Playwright)
    → 로컬 음성 저장
    → Whisper 음성 인식 (Python)
    → Obsidian Vault 저장
    → (선택) 후단에서 LLM 요약
참고: PLAUD는 연속 녹음을 해도 하나의 거대한 파일로 끝없이 늘어나지 않는다. 실제 운용 기준으로 약 5시간마다 녹음 파일이 자동 분할된다. 따라서 생활 로그 용도로 하루 종일 돌리면, 하루치 기록은 자연스럽게 여러 파일로 나뉜다.

이 구성에서 날짜별 Markdown으로 묶는 이유는, 이렇게 분할된 녹음을 나중에 시간순으로 재통합해 사람에게도 AI에게도 다루기 쉬운 형태로 만들기 위해서다.

사전 준비: 디렉토리 구성은 처음부터 대충 하지 않는다

먼저 권장 구성부터 시작하자. 상세 이름은 마음대로 바꿔도 되지만, 역할만큼은 반드시 나눠 둬야 한다.

plaud-pipeline/
├─ plaud_login_and_download.js    # Plaud Web 로그인 및 토큰 취득
├─ plaud_download_audio.js        # 음성 파일 다운로드 및 폴더 이동
├─ whisper.py                     # 로컬 음성 인식 및 Obsidian 저장
├─ plaud_daily_pipeline.ps1       # 전체 파이프라인 정기 실행 스크립트
└─ input/                         # PLAUD에서 새로 받아온 음성 (임시)

Obsidian Vault/
└─ Transcripts/
   ├─ 2026-03-20.md
   ├─ 2026-03-21.md
   └─ ...

processed audio/                   # 처리 완료 음성 보관 장소
└─ 2026-03-20 08_30_10.mp3        # 외장 HDD 또는 클라우드 스토리지 (Google Drive 등)
구조의 핵심 개념은 이렇다.

폴더

역할

input/

미처리 임시 폴더 — 처리 후 즉시 비워진다

processed audio/

처리 완료 원본 음성 아카이브

Transcripts/

사람과 AI가 읽는 날짜별 본문

필요한 것

PLAUD 계정

Node.js (v18 이상 권장)

Playwright (npm install playwright)

Python 3.10 이상

faster-whisper (pip install faster-whisper)

Obsidian (Vault 경로 확보)

Windows 작업 스케줄러

(선택) 후단 요약용 OpenClaw 또는 임의의 LLM API

GPU 관련: GPU가 있으면 Whisper 처리 속도가 크게 달라지지만, 어차피 자고 있는 동안 알아서 돌아가는 구성이므로 시간 자체는 크게 중요하지 않다. CPU로도 충분히 동작한다.

한국어 인식 정확도: Whisper의 한국어 인식 품질은 꽤 좋다. 특히 large-v3-turbo 모델은 한국어 구어체도 잘 인식한다. 다만 전문 용어나 고유명사가 많은 경우에는 후단에서 LLM으로 정정하는 것이 효과적이다.

1단계: Plaud Web에 로그인해서 토큰을 얻는다

출발점은 Plaud Web이다.

이유는 간단하다. 상시 녹음에 가까운 운용이라면, 앱을 매번 조작하는 전제 자체가 이미 번거롭기 때문이다. UI를 열어서 선택하고 내리는 운용은 생활 로그 용도와 궁합이 좋지 않다.

Plaud Web 쪽이 다소 까다로운 인증 구조를 갖고 있어, 단순히 Playwright로 로그인 화면을 자동 조작하는 것만으로는 부족했다. 이 부분에서는 로그인 후 브라우저 쪽에서 성립된 인증 상태를 취득하고, 후단의 다운로드 처리로 넘기는 형태로 구현하고 있다.

​

plaud_login_and_download.js

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
    moveToFolderId: null,
    downloadDir: null,
    limit: 9999,
    apiBase: null,
    headless: false,
    download: true,
    verbose: false
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
    console.error('PLAUD_EMAIL / PLAUD_PASSWORD를 설정해 주세요');
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

    await page.fill('input[placeholder="이메일 주소"]', email);
    await page.fill('input[placeholder="비밀번호"]', password);
    await page.click('button:has-text("로그인"), button:has-text("Login")');

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
2단계. 녹음 목록을 가져와서 자동 다운로드하고 처리 완료 폴더로 이동시킨다

여기가 핵심이다.

여기서 하는 것은, 클라우드에 업로드되어 자동으로 분류되는 "미분류" 폴더에서 녹음 목록을 가져오고, 대상 음성을 다운로드해, 완료 후 PLAUD 쪽에서 처리 완료 폴더로 이동시키는 것이다. 이로써 처리 완료 파일을 다시 다운로드하는 것을 방지한다.

​

plaud_download_audio.js

#!/usr/bin/env node
const fs = require('node:fs');
const path = require('node:path');
const { pipeline } = require('node:stream/promises');

// 한국 사용자의 경우 apne1이 일반적이지만, api.plaud.ai가 무난한 경우도 있습니다.
// 연결이 안 되면 --api-base https://api.plaud.ai 를 시도해 보세요.
const DEFAULT_API_BASE = 'https://api-apne1.plaud.ai'; 
const DEFAULT_DOWNLOAD_DIR = 'downloads/plaud';

function parseArgs() {
  const args = process.argv.slice(2);
  const options = {
    folderName: '미분류',
    limit: 9999,
    downloadDir: DEFAULT_DOWNLOAD_DIR,
    moveToFolderId: null,
    folderId: null,
    token: null,
    verbose: false,
    apiBase: DEFAULT_API_BASE
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
    'referer': 'https://web.plaud.ai/'
  };
}

// 파일명을 안전한 문자만으로 변환
function toSafeFilename(str) {
  return str.replace(/[\\/:*?"<>|]/g, '_').trim();
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

  // 1. 태그(폴더) 정보 취득
  let tagMap = {};
  try {
      const tagRes = await fetch(`${options.apiBase}/filetag/`, { headers });
      const tagData = await tagRes.json();
      if(tagData.data_filetag_list) {
          tagData.data_filetag_list.forEach(t => tagMap[t.id] = t.name);
      }
  } catch(e) { console.warn("태그 취득 실패, 계속 진행합니다..."); }

  // 2. 파일 목록 취득
  const listParams = new URLSearchParams({
      skip: '0', limit: String(options.limit), is_trash: '0', sort_by: 'start_time', is_desc: 'true'
  });
  if (options.folderId) listParams.append('folderId', options.folderId);

  const listRes = await fetch(`${options.apiBase}/file/simple/web?${listParams}`, { headers });
  if (!listRes.ok) throw new Error(`목록 취득 실패: ${listRes.status}`);
  
  const listData = await listRes.json();
  const allFiles = listData.data_file_list || [];

  // 3. 폴더명으로 필터링
  const targetFiles = allFiles.filter(f => {
      // 태그 ID 목록의 첫 번째를 폴더로 간주
      const tagId = (f.filetag_id_list && f.filetag_id_list[0]) ? f.filetag_id_list[0] : null;
      const tagName = tagId ? tagMap[tagId] : '미분류';
      return tagName === options.folderName;
  });

  console.log(`"${options.folderName}"에서 ${targetFiles.length}개 파일 발견.`);

  for (const file of targetFiles) {
      const fileId = file.fileId || file.id;
      const fileName = toSafeFilename(file.filename || file.title || `audio_${fileId}`);
      
      try {
          // 다운로드 URL 취득
          const urlRes = await fetch(`${options.apiBase}/file/temp-url/${fileId}`, { headers });
          if(!urlRes.ok) continue;
          const urlData = await urlRes.json();
          const downloadUrl = urlData.data?.temp_url || urlData.temp_url;
          
          if (!downloadUrl) {
              console.warn(`${fileName}의 URL 없음`);
              continue;
          }

          // 확장자 추정
          const ext = path.extname(new URL(downloadUrl).pathname) || '.mp3';
          const destPath = path.join(options.downloadDir, `${fileName}${ext}`);

          console.log(`다운로드 중: ${fileName}${ext}`);
          const fileRes = await fetch(downloadUrl);
          await pipeline(fileRes.body, fs.createWriteStream(destPath));

          // 폴더 이동 처리
          if (options.moveToFolderId) {
              const moveRes = await fetch(`${options.apiBase}/file/update-tags`, {
                  method: 'POST',
                  headers: { ...headers, 'content-type': 'application/json' },
                  body: JSON.stringify({ file_id_list: [fileId], filetag_id: options.moveToFolderId })
              });
              if(moveRes.ok) console.log(`  -> 폴더 ID로 이동 완료: ${options.moveToFolderId}`);
          }

      } catch (err) {
          console.error(`${fileName} 처리 실패: ${err.message}`);
      }
  }
}

main().catch(e => { console.error(e); process.exit(1); });
3단계: PowerShell로 전체를 정기 실행한다

Windows 기기를 서버로 사용하고 있으므로, PowerShell 스크립트를 작업 스케줄러에 등록한다.

내용은 정기 실행용 얇은 래퍼로, Node 쪽의 취득 처리와 Python 쪽의 음성 인식 처리를 순서대로 호출할 뿐이다.

plaud_daily_pipeline.ps1로 저장하고, 원하는 시간에 작업 스케줄러를 설정한다.

param(
    [string]$PlaudEmail = "Plaud 로그인 이메일 주소",
    [string]$PlaudPassword = "Plaud 비밀번호",
    [int]$DownloadLimit = 9999
)

if (-not $PlaudEmail -or -not $PlaudPassword) {
    throw 'PLAUD_EMAIL과 PLAUD_PASSWORD를 파라미터 또는 환경 변수로 제공해야 합니다.'
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
Push-Location $scriptDir

$InputAudioDir = Join-Path $scriptDir 'input'
$LogDir = Join-Path $scriptDir 'logs'
$timestamp = Get-Date -Format 'yyyy-MM-dd_HHmm'
$DownloadLog = Join-Path $LogDir "plaud_download_$timestamp.log"

# 디렉토리 생성
foreach ($dir in @($InputAudioDir, $LogDir)) {
    if (-not (Test-Path $dir)) { 
        New-Item -ItemType Directory -Path $dir -Force | Out-Null 
    }
}

Write-Output "===== 시작: $timestamp =====" | Tee-Object -FilePath $DownloadLog

# ---------------------------------------------------------
# Step 1: Playwright 헬퍼(Node.js)를 통해 다운로드
# ---------------------------------------------------------
Write-Output "--- 다운로드 시작 ---" | Tee-Object -FilePath $DownloadLog -Append

# 중요: 필요 시 수동으로 CAPTCHA를 풀 수 있도록 "--headless"를 제거했습니다.
$nodeArgs = @(
    "plaud_login_and_download.js",
    "--email", $PlaudEmail,
    "--password", $PlaudPassword,
    "--move-to-folder-id", "다운로드 후 이동시킬 PlaudWeb 상의 폴더 ID",
    "--limit", "$DownloadLimit",
    "--download-dir", $InputAudioDir,
    "--verbose"
)

# Node.js 호출
& node $nodeArgs 2>&1 | Tee-Object -FilePath $DownloadLog -Append

if ($LASTEXITCODE -ne 0) {
    Write-Error "다운로드 스크립트 실패. 로그를 확인하세요."
    Start-Sleep -Seconds 5
    exit 1
}

# ---------------------------------------------------------
# Step 2: Python 스크립트를 통해 음성 인식
# ---------------------------------------------------------
Write-Output "--- 음성 인식 시작 ---" | Tee-Object -FilePath $DownloadLog -Append

$pythonArgs = @(
    "whisper.py"
)

& python $pythonArgs 2>&1 | Tee-Object -FilePath $DownloadLog -Append

if ($LASTEXITCODE -ne 0) {
    Write-Error "Python 스크립트 실패. 로그를 확인하세요."
    Start-Sleep -Seconds 5
    exit 1
}

Write-Output "===== 종료: $(Get-Date -Format 'yyyy-MM-dd_HHmm') =====" | Tee-Object -FilePath $DownloadLog -Append

Write-Output "모든 작업이 완료되었습니다."
Start-Sleep -Seconds 3
macOS 사용자의 경우, Bash쉘로 실행하는 쉘 프로그램도 공유한다.

​

plaud_daily_pipeline.sh

#!/usr/bin/env bash
# ============================================================
# 사용법:
#   ./run.sh [이메일] [비밀번호] [다운로드_한도(선택)]
#
# 또는 환경 변수로 지정:
#   export PLAUD_EMAIL="your@email.com"
#   export PLAUD_PASSWORD="yourpassword"
#   ./run.sh
# ============================================================

set -euo pipefail

# ---------------------------------------------------------
# 파라미터 / 환경 변수 처리
# ---------------------------------------------------------
PLAUD_EMAIL="${1:-${PLAUD_EMAIL:-}}"
PLAUD_PASSWORD="${2:-${PLAUD_PASSWORD:-}}"
DOWNLOAD_LIMIT="${3:-9999}"

if [[ -z "$PLAUD_EMAIL" || -z "$PLAUD_PASSWORD" ]]; then
    echo "오류: PLAUD_EMAIL과 PLAUD_PASSWORD를 인수 또는 환경 변수로 제공해야 합니다." >&2
    echo "사용법: $0 <이메일> <비밀번호> [다운로드_한도]" >&2
    exit 1
fi

# ---------------------------------------------------------
# 디렉토리 설정
# ---------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

INPUT_AUDIO_DIR="$SCRIPT_DIR/input"
LOG_DIR="$SCRIPT_DIR/logs"
TIMESTAMP="$(date '+%Y-%m-%d_%H%M')"
DOWNLOAD_LOG="$LOG_DIR/plaud_download_${TIMESTAMP}.log"

mkdir -p "$INPUT_AUDIO_DIR" "$LOG_DIR"

# 로그 + 콘솔 동시 출력 함수
log() {
    echo "$*" | tee -a "$DOWNLOAD_LOG"
}

log "===== 시작: $TIMESTAMP ====="

# ---------------------------------------------------------
# Step 1: Playwright 헬퍼(Node.js)를 통해 다운로드
# ---------------------------------------------------------
log "--- 다운로드 시작 ---"

node plaud_login_and_download.js \
    --email        "$PLAUD_EMAIL" \
    --password     "$PLAUD_PASSWORD" \
    --move-to-folder-id "다운로드 후 이동시킬 PlaudWeb 상의 폴더 ID" \
    --limit        "$DOWNLOAD_LIMIT" \
    --download-dir "$INPUT_AUDIO_DIR" \
    --verbose \
    2>&1 | tee -a "$DOWNLOAD_LOG"

# tee는 파이프 앞 명령의 종료 코드를 삼키므로 PIPESTATUS로 확인
if [[ "${PIPESTATUS[0]}" -ne 0 ]]; then
    echo "오류: 다운로드 스크립트 실패. 로그를 확인하세요: $DOWNLOAD_LOG" >&2
    sleep 5
    exit 1
fi

# ---------------------------------------------------------
# Step 2: Python 스크립트를 통해 음성 인식
# ---------------------------------------------------------
log "--- 음성 인식 시작 ---"

python3 whisper.py 2>&1 | tee -a "$DOWNLOAD_LOG"

if [[ "${PIPESTATUS[0]}" -ne 0 ]]; then
    echo "오류: Python 스크립트 실패. 로그를 확인하세요: $DOWNLOAD_LOG" >&2
    sleep 5
    exit 1
fi

log "===== 종료: $(date '+%Y-%m-%d_%H%M') ====="
log "모든 작업이 완료되었습니다."
sleep 3
실행 방법(macOS)

# 실행 권한 부여 (최초 1회)
chmod +x plaud_daily_pipeline.sh

# 인수로 실행
./plaud_daily_pipeline.sh your@email.com yourpassword

# 환경 변수로 실행
export PLAUD_EMAIL="your@email.com"
export PLAUD_PASSWORD="yourpassword"
./plaud_daily_pipeline.sh
폴더 ID 확인 방법

Plaud Web에 등록한 로그인 이메일/비밀번호, 그리고 --move-to-folder-id에 지정하는 폴더 ID는 환경에 따라 다르다. 각자 환경에 맞게 수정할 것.

이동 대상 폴더 ID 취득 방법: Plaud Web 왼쪽 패널에서 대상 폴더를 선택하고 URL을 확인한다.

https://web.plaud.ai/file-list?tagId=a6fd8e0b3d95186c2dc6841e76913e2c&categoryId=...
이 URL에서 tagId= 뒤에 오는 a6fd8e0b3d95186c2dc6841e76913e2c 부분이 폴더 ID에 해당한다.

​

4단계: faster-whisper로 로컬 음성 인식을 한다

앞 단계에서 음성을 받아왔으면, 다음은 음성 인식이다. 여기서는 PLAUD의 요약 기능을 쓰지 않고, 로컬 Whisper로 처리한다.

로컬에서 하는 이유는 명확하다.

분 단위 과금에 묶이지 않는다

원본 음성에서 직접 재처리할 수 있다

요약 전의 원문 로그를 자산으로 보유할 수 있다

후단의 AI를 자유롭게 교체할 수 있다

수집한 음성을 파일명 기준으로 시간순 정렬하고, faster-whisper로 음성 인식하고, 음성 파일명의 시작 시각을 기준으로 절대 시각이 붙은 로그로 변환해서, 날짜별 Markdown에 추가 기입한다.

​

whisper.py

import os
import shutil
from datetime import datetime, timedelta
from faster_whisper import WhisperModel

# ====== 설정 ======
INPUT_DIR = "./input"           # 입력 음성 파일 저장 폴더
PROCESSED_DIR = r"D:\rec\sound" # 처리 후 보관 폴더
                                # Google Drive, Naver MYBOX, OneDrive 등 동기화 폴더 경로도 가능
OUTPUT_DIR = r"C:\Users\사용자명\Obsidian\Vault\Transcripts"  # Obsidian Vault 내 Transcripts 폴더
MODEL_SIZE = "large-v3-turbo"
DEVICE = "cuda"                 # GPU가 없는 경우 "cpu"
COMPUTE_TYPE = "float16"        # CPU라면 "int8"
BEAM_SIZE = 5

LANGUAGE = "ko"                 # 한국어
TASK = "transcribe"
# ==================

def parse_start_dt(filename: str) -> datetime:
    """
    파일명에서 녹음 시작 시각을 파싱합니다.
    지원 형식: '2026-03-19 08_30_10.mp3' 또는 '2026-03-19_08_30_10.mp3'
    """
    base = os.path.splitext(filename)[0].strip()
    for fmt in ("%Y-%m-%d %H_%M_%S", "%Y-%m-%d_%H_%M_%S"):
        try:
            return datetime.strptime(base, fmt)
        except ValueError:
            continue
    raise ValueError(f"파일명 형식 오류 (지원 형식: YYYY-MM-DD HH_MM_SS): {filename}")

def transcribe_collect(model: WhisperModel, file_path: str):
    file = os.path.basename(file_path)
    start_dt = parse_start_dt(file)
    date_key = start_dt.strftime("%Y-%m-%d")
    split_key = start_dt.strftime("%Y-%m-%d_%H-%M-%S")

    segments, info = model.transcribe(
        file_path,
        task=TASK,
        language=LANGUAGE,
        vad_filter=True,
        # 기본 VAD보다 문맥을 너무 잘라내지 않는 느슨한 VAD 설정
        # 생활 로그 용도에서는 누락을 줄이는 쪽이 중요
        vad_parameters=dict(
            min_silence_duration_ms=5000,  # 5초 이상 무음에서 분할
            speech_pad_ms=1000,            # 전후 1초 여백 부여
        ),
        beam_size=BEAM_SIZE,
        temperature=0.0,
        condition_on_previous_text=False,
    )

    rows = []
    for seg in segments:
        if not seg.text:
            continue
        abs_start = start_dt + timedelta(seconds=seg.start)
        line = f"[{abs_start.strftime('%H:%M:%S')}] {seg.text.strip()}"
        rows.append((abs_start, line))

    return date_key, split_key, rows

def main():
    print("CWD:", os.getcwd())

    os.makedirs(INPUT_DIR, exist_ok=True)
    os.makedirs(PROCESSED_DIR, exist_ok=True)
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    targets = [f for f in os.listdir(INPUT_DIR)
               if f.lower().endswith((".mp3", ".wav", ".m4a", ".flac"))]
    targets.sort()

    if not targets:
        print("처리 대상 없음: input 폴더가 비어 있습니다.")
        return

    print(f"모델 로딩 중: {MODEL_SIZE}...")
    try:
        model = WhisperModel(MODEL_SIZE, device=DEVICE, compute_type=COMPUTE_TYPE)
    except Exception as e:
        print(f"모델 시작 오류: {e}")
        return

    print(f"처리 시작: {len(targets)}개 파일")

    for i, f in enumerate(targets, 1):
        src = os.path.join(INPUT_DIR, f)
        print(f"[{i}/{len(targets)}] 분석 중... {f}")

        try:
            # 1. 음성 인식 실행
            date_key, split_key, rows = transcribe_collect(model, src)

            if not rows:
                print(f"  -> 음성 데이터 없음 (스킵): {f}")
            else:
                # 2. 날짜별 파일에 추가 기입
                out_daily = os.path.join(OUTPUT_DIR, f"{date_key}.md")
                with open(out_daily, "a", encoding="utf-8") as w:
                    for _, line in rows:
                        w.write(line + "\n")

                print(f"  -> 출력 완료: {date_key}.md (추가 기입)")

            # 3. 처리 완료 이동
            dst = os.path.join(PROCESSED_DIR, f)
            shutil.move(src, dst)
            print(f"  -> 이동 완료: {f}")

        except Exception as e:
            print(f"오류 발생 ({f}): {e}")
            continue

    print("모든 처리가 완료되었습니다.")

if __name__ == "__main__":
    main()
경로 설정 주의: PROCESSED_DIR와 OUTPUT_DIR는 각자 환경에 맞게 반드시 수정할 것. Obsidian Vault의 위치는 Obsidian 앱 설정에서 확인할 수 있다.

macOS 사용자도 Windows기반 경로를 확인하고 변경해서 사용해야 한다.

파일명에 시각을 담는 것의 의미

이 스크립트에서 가장 중요한 포인트는, 파일명에 녹음 시작 시각을 갖게 하는 것이다. 그 시각을 기준으로, Whisper가 출력하는 상대 시간을 절대 시각이 붙은 로그로 변환한다.

출력 예시는 이렇게 된다.

[08:31:12] 안녕, 오늘 일정이 어떻게 돼?
[08:31:40] 오전에 회의가 하나 있고 오후는 비어있어
[08:34:02] 그럼 오후에 같이 카페 가자
이 형식을 유지하면:

사람이 그대로 읽을 수 있다

Obsidian에서 일간 노트로 다루기 쉽다

후단의 AI에게 요약이나 행동 로그 추출을 맡길 때도 그대로 넘길 수 있다

1 녹음 1 파일보다, 날짜별 Markdown에 시간순으로 추가 기입하는 편이 실용적이다. 진지하게 다시 볼 거라면, 하루치를 통째로 읽을 수 있는 형태 쪽이 훨씬 강하다.

​

VAD 설정에 대해

VAD(음성 활동 감지) 관련 설정은 취향이 크게 갈린다. 깔끔한 자막을 만들고 싶은지, 생활 로그로서 누락을 최소화하고 싶은지에 따라 최적값이 달라지므로, 각자의 운용에 맞게 조정하기 바란다.

장시간 음성에서도 너무 잘리지 않으면서, 할루시네이션을 억제하기 위해 꽤 느슨하게 설정하고 있다.

min_silence_duration_ms=5000   # 5초 이상 무음에서 분할
speech_pad_ms=1000             # 전후 1초 여백
condition_on_previous_text=False
어느 정도는 VAD를 넣어두지 않으면 환각이 대량으로 발생한다. Whisper가 YouTube 음성으로 학습되어 있기 때문인지, 무음 구간에 "구독과 좋아요 부탁드립니다" 같은 엉뚱한 음성 인식이 섞여 들어오는 일이 있다. 한국어의 경우 이 현상이 꽤 빈번하므로 주의가 필요하다.

깔끔한 음성 인식 결과를 원한다면, 후단에서 LLM에게 정형화시키는 것이 효과적이다.

​

5단계: Obsidian Vault에 어떻게 배치할 것인가

여기도 은근히 중요한 포인트다. AI 관련 글에서는 건너뛰기 쉽지만, 실제로는 음성 인식 후의 배치 방식 쪽이 장기적인 가치를 결정한다.

권장 구성은 이렇다.

Vault/
├─ Transcripts/          ← 원문 로그 (자동 저장)
│  ├─ 2026-03-20.md
│  ├─ 2026-03-21.md
│  └─ ...
├─ Daily Summary/        ← 요약 로그 (수동 또는 자동)
│  ├─ 2026-03-20_summary.md
│  └─ ...
└─ Projects/             ← 프로젝트별 발췌 및 정리
의식하는 포인트는 원문 로그 / 요약 로그 / 중요 사항 발췌를 나누는 것이다.

전부 하나로 섞으면 나중에 읽을 수 없다. 그렇다고 너무 세밀하게 나누면 번거롭다. 그래서 최소한의 3층 구조만 유지한다.

​

왜 날짜별 파일인가

이유는 단순하다. 그날의 흐름이 한눈에 보인다. 요약하기 쉽다. AI에게 넘기기 쉽다. 사람이 다시 봐도 이해하기 쉽다.

녹음마다 파일이 대량으로 늘어서는 구성은 보기에는 정돈되어 보이지만 실제 운용에서는 약하다. 진지하게 쓴다면, 시간순으로 하루치를 통째로 읽을 수 있는 형태 쪽이 훨씬 강하다.

​

6단계: OpenClaw를 쓰는 경우, 쓰지 않는 경우

요즘은 OpenClaw를 사용하고 있다. 이유는 단순히 요약 결과를 읽는 것만이 아니라, 그 내용을 OpenClaw 쪽의 지속적 컨텍스트에도 축적하고 싶었기 때문이다. 단, 이것은 필수가 아니다. 여기는 제대로 구분해 두고 싶다.

​

OpenClaw를 쓰는 경우

날짜별 Markdown을 모니터링하고, 일정 시간마다 추가분을 요약한다. 생활 로그의 요점이나 태스크 후보를 추출해, 그대로 OpenClaw 쪽의 메모리에도 축적한다.

요약에는 다음 템플릿을 Vault에 배치하고, 이에 따라 만들도록 지시하고 있다. (원본은 Plaud 공식 템플릿을 참고해 한국어 환경에 맞게 조정한 것)

당신은 ADHD가 있는 사용자의 하루 전체 음성 녹음을 요약하는 역할입니다.
사용자가 다시 듣거나 다시 읽지 않아도 하루를 완전히 파악할 수 있도록 도와주세요.

시각적으로 정리된 ADHD 친화적인 요약을 다음 구조로 작성해 주세요:

📌 핵심 요점 5가지
오늘의 가장 중요한 순간, 결정, 사건을 굵은 글씨 한 줄로 요약.

🕒 시간순 타임라인
시간대별로 분류해 주세요 (예: "오전 9:00–9:45"):

☀️ 오전 (6시~12시)
🌤️ 점심 (12시~15시)
🌇 오후 (15시~18시)
🌙 저녁 (18시 이후)

각 블록: 짧은 글머리 요점. 관련 인물, 사건, 핵심 주제 포함. 큰 일이 없으면 "(조용한 시간대)" 표기.

👥 대화 및 미팅
각 대화별:
🧑‍🤝‍🧑 참여자
🗣️ 주요 내용 (간략히)
✅ 결과 또는 후속 조치

💭 개인 생각 및 아이디어
💡 새로운 아이디어
🤔 제기된 질문
✨ 창의적 번뜩임
😖 걱정 또는 감정적 고민

📋 할 일 & 리마인더
[ ] 할 일 1
[ ] 할 일 2
🏠 집안일 / 💼 업무 / 💰 재정 / 🧠 자기관리 등으로 분류

🛍️ 구매 목록
언급된 구매 필요 항목 (카테고리별 분류)

🎯 내린 결정들
✔️ 결정 내용
❓ 영향 범위

🔁 반복되는 주제 또는 어려움
패턴 파악에 도움이 되는 반복 언급 사항

🗣️ 기억에 남는 발언 3~5개
타임스탬프와 함께 (가능하면 말투도 메모: "진지하게", "감정적으로" 등)

⚡ 다음 할 일
[ ] ___에게 연락
[ ] 내일을 위해 ___ 준비
[ ] ___ 에 대해 돌아보기

🧐 중요할 수도 있는 것
분류하기 애매하지만 버리기는 아까운 내용 보관

답변은 반드시 한국어로 작성하세요.
OpenClaw를 쓰지 않는 경우

날짜별 Markdown을 보존해 두고, 필요할 때만 API로 요약시킨다. 주간 또는 일간 단위로 수동·반자동으로 돌리는 형태로도 충분히 기능한다.

이 글의 주인공은 OpenClaw 그 자체가 아니다. 어디까지나 전단의 "수집 → 음성 인식 → 저장" 이다. 여기만 제대로 되어 있으면, 후단은 원하는 도구로 자유롭게 교체할 수 있다.

​

실제 운용에서 애로사항

이런 류의 글은 성공 경험만 쓰면 내용이 빈약해진다. 실제로 막히기 쉬운 곳을 정리해 둔다.

로그인 UI는 예고 없이 바뀐다. Playwright로 UI를 다루는 이상, 입력란이나 버튼의 셀렉터가 바뀌는 일은 있다. 이건 피할 수 없다. 그래서 로그인 처리는 처음부터 독립시켜 두는 것이다.

토큰의 저장 방식도 바뀔 수 있다. localStorage / sessionStorage의 어디에 어떤 이름으로 들어가는지는 앞으로 바뀔 수 있다. 취득 후보를 여러 개 확인해 두는 것이 무난하다.

파일명의 시각 형식은 반드시 통일한다. 후단의 절대 시각 로그 생성이 파일명에 의존하고 있다. 이 규칙이 무너지면 전체 파이프라인이 망가진다.

Whisper는 저사양 PC에서는 무겁다. RTX 4070 Ti Super로 large-v3-turbo를 돌리면 하루치가 약 10분에 완료된다. CPU로 돌리더라도 자는 동안 알아서 처리되므로, 속도 자체는 크게 문제가 되지 않는다.

원본 음성은 생각보다 용량을 많이 차지한다. 5시간 파일이 약 70MB. 매일 녹음하면 하루에 약 300MB가 된다. 저장 위치는 처음부터 나눠 두는 게 좋다. Google Drive, Naver MYBOX, OneDrive 등 클라우드 스토리지와 연동하면 관리가 편하다. 음성 인식본이 있으면 원본 음성은 필요 없다는 결단도 충분히 합리적이다.

한국어 고유명사·신조어 오인식 문제. Whisper의 한국어 인식은 전반적으로 훌륭하지만, 인명·지명·전문 용어·최신 신조어는 오인식이 발생할 수 있다. 중요한 내용이 포함된 구간은 후단에서 LLM으로 보정하는 것을 권장한다.

​

환경 구축 체크리스트

처음 설정할 때 누락되기 쉬운 항목 모음.

Node.js 설치 및 npm install playwright 완료

npx playwright install chromium 실행 (브라우저 드라이버 설치)

Python 및 pip install faster-whisper 완료

GPU 사용 시 CUDA 버전 확인 (nvidia-smi 로 확인)

Obsidian Vault 경로 확인 및 Transcripts 폴더 생성

plaud_daily_pipeline.ps1에 이메일/비밀번호/폴더ID 입력

whisper.py의 PROCESSED_DIR, OUTPUT_DIR 경로 수정

Windows 작업 스케줄러 등록 (PowerShell 스크립트 경로 지정)

Plaud Web에서 "처리완료" 등 이동용 폴더 생성 및 폴더 ID 확인

​

PLAUD를 "AI가 알아서 요약해 주는 녹음기"로만 쓴다면, 여기까지 할 필요는 없을 것이다. 하지만 깨어 있는 동안 거의 상시 녹음해서, 자신의 생활을 제대로 기록하고 자산으로 만들고 싶다면, 결국 필요한 건 이런 소박한 배관이다.

녹음한다 → 동기화된다 → 수집한다 → 텍스트로 만든다 → 남긴다 → 필요할 때 쓴다.

이 흐름이 한 번 돌아가기 시작하면, 남은 건 후단을 어떻게 활용할 것인가의 문제만 남는다.

참고로, 코드를 꼼꼼히 읽은 분은 눈치챘을 수 있지만, 사그라다 파밀리아처럼 계속 덧붙이며 키워온 탓에 스크립트 내에 결국 사용하지 않는 인수도 남아 있다. 각자 환경에 맞게 적당히 개조해서 활용하기 바란다.


