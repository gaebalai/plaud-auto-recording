#!/usr/bin/env bash
# PLAUD 파이프라인 자동 설치 (macOS 전용)
#
# 사용법:
#   ./setup.sh           # 풀 설치
#   ./setup.sh --check   # 점검만 (변경 없음)
#   ./setup.sh --yes     # 확인 없이 자동 진행
#   ./setup.sh --help
set -euo pipefail

# ---------- 색상 ----------
if [[ -t 1 ]]; then
    GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'
    BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'
else
    GREEN=''; YELLOW=''; RED=''; BLUE=''; BOLD=''; RESET=''
fi
ok()   { printf "${GREEN}✓${RESET} %s\n" "$*"; }
info() { printf "${BLUE}·${RESET} %s\n" "$*"; }
warn() { printf "${YELLOW}⚠${RESET} %s\n" "$*"; }
err()  { printf "${RED}✗${RESET} %s\n" "$*" >&2; }
hdr()  { printf "\n${BOLD}== %s ==${RESET}\n" "$*"; }

# ---------- 인수 ----------
CHECK_ONLY=false
ASSUME_YES=false
for arg in "$@"; do
    case "$arg" in
        --check)     CHECK_ONLY=true ;;
        --yes|-y)    ASSUME_YES=true ;;
        -h|--help)
            cat <<EOF
사용법:
  ./setup.sh           # 풀 설치
  ./setup.sh --check   # 점검만 (변경 없음)
  ./setup.sh --yes     # 확인 프롬프트 없이 자동 진행

수행 작업:
  1) Node.js / Python / Homebrew 점검
  2) 프로젝트 로컬에 npm install playwright
  3) Playwright Chromium 다운로드
  4) Python venv (.venv) 생성 + faster-whisper 설치
  5) 디렉토리 준비 (input/, logs/, ~/PLAUD-Data, Obsidian Vault 폴더)
  6) .env 파일 생성 (없을 때만 .env.example 복사)
  7) 스크립트 실행 권한 부여
EOF
            exit 0
            ;;
    esac
done

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

VAULT_BASE="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents"

# ---------- 1. 시스템 점검 ----------
hdr "1. 시스템 점검"

if [[ "$(uname)" != "Darwin" ]]; then
    err "이 스크립트는 macOS 전용입니다. (현재: $(uname))"
    exit 1
fi
ok "macOS"

NEED_NODE=false
NEED_PY=false

if command -v node >/dev/null 2>&1; then
    NODE_VER="$(node --version | sed 's/v//')"
    NODE_MAJOR="${NODE_VER%%.*}"
    if [[ "$NODE_MAJOR" -lt 18 ]]; then
        warn "Node.js v$NODE_VER (v18 이상 필요)"
        NEED_NODE=true
    else
        ok "Node.js v$NODE_VER"
    fi
else
    warn "Node.js 미설치"
    NEED_NODE=true
fi

if command -v python3 >/dev/null 2>&1; then
    PY_VER="$(python3 --version | awk '{print $2}')"
    PY_MAJOR="${PY_VER%%.*}"
    PY_MINOR="$(echo "$PY_VER" | cut -d. -f2)"
    if [[ "$PY_MAJOR" -lt 3 ]] || { [[ "$PY_MAJOR" -eq 3 ]] && [[ "$PY_MINOR" -lt 10 ]]; }; then
        warn "Python $PY_VER (3.10 이상 필요)"
        NEED_PY=true
    else
        ok "Python $PY_VER"
    fi
else
    warn "Python3 미설치"
    NEED_PY=true
fi

HAS_BREW=false
if command -v brew >/dev/null 2>&1; then
    ok "Homebrew 사용 가능"
    HAS_BREW=true
else
    warn "Homebrew 없음 (Node/Python 설치에 필요할 수 있음)"
fi

# Obsidian Vault 점검
if [[ -d "$VAULT_BASE" ]]; then
    ok "Obsidian Vault 발견: $VAULT_BASE"
else
    warn "Obsidian Vault 경로 없음: $VAULT_BASE"
    info "Vault가 다른 곳이라면 .env에 PLAUD_OUTPUT_DIR로 지정하세요."
fi

# 누락 패키지 안내
if $NEED_NODE || $NEED_PY; then
    hdr "필요한 시스템 패키지 설치"
    if $HAS_BREW; then
        info "Homebrew로 설치할 수 있습니다:"
        $NEED_NODE && echo "    brew install node"
        $NEED_PY   && echo "    brew install python@3.11"
    else
        info "먼저 Homebrew를 설치하세요:"
        echo '    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
        info "그 다음:"
        $NEED_NODE && echo "    brew install node"
        $NEED_PY   && echo "    brew install python@3.11"
    fi
    err "위 패키지 설치 후 ./setup.sh 를 다시 실행해 주세요."
    exit 1
fi

# 점검 모드면 여기서 종료
if $CHECK_ONLY; then
    hdr "프로젝트 상태"
    [[ -d "$PROJECT_DIR/node_modules/playwright" ]] && ok "playwright 설치됨" || warn "playwright 미설치"
    [[ -d "$PROJECT_DIR/.venv" ]] && ok ".venv 존재" || warn ".venv 없음"
    if [[ -d "$PROJECT_DIR/.venv" ]]; then
        if "$PROJECT_DIR/.venv/bin/python3" -c "import faster_whisper" 2>/dev/null; then
            ok "faster-whisper 설치됨"
        else
            warn "faster-whisper 미설치"
        fi
    fi
    [[ -f "$PROJECT_DIR/.env" ]] && ok ".env 존재" || warn ".env 없음"
    [[ -d "$HOME/PLAUD-Data" ]] && ok "~/PLAUD-Data 존재" || warn "~/PLAUD-Data 없음"
    [[ -d "$HOME/.plaud-pipeline-profile" ]] && ok "구글 로그인 세션 프로필 존재" || info "구글 로그인 세션 미설정 (session 모드 사용 시 필요)"

    # .env가 있으면 PLAUD_OUTPUT_DIR override를 반영
    VAULT_OUTPUT_CHECK="${PLAUD_OUTPUT_DIR:-}"
    if [[ -z "$VAULT_OUTPUT_CHECK" && -f "$PROJECT_DIR/.env" ]]; then
        VAULT_OUTPUT_CHECK="$(grep -E '^PLAUD_OUTPUT_DIR=' "$PROJECT_DIR/.env" 2>/dev/null | sed 's/^[^=]*=//' | sed 's/^"//; s/"$//' || true)"
    fi
    [[ -z "$VAULT_OUTPUT_CHECK" ]] && VAULT_OUTPUT_CHECK="$VAULT_BASE/Transcripts"

    hdr "Obsidian Vault 점검"
    info "Transcripts 경로: $VAULT_OUTPUT_CHECK"
    if [[ -d "$VAULT_OUTPUT_CHECK" ]]; then
        ok "Transcripts 폴더 존재"
        VAULT_TEST="$VAULT_OUTPUT_CHECK/.plaud_write_test_$$"
        if ( : > "$VAULT_TEST" ) 2>/dev/null; then
            ok "  쓰기 권한 OK"
            rm -f "$VAULT_TEST"
        else
            warn "  쓰기 권한 없음 — 시스템 설정 > 개인정보 보호 및 보안 > 전체 디스크 접근 확인"
        fi
    else
        warn "Transcripts 폴더 없음 (./setup.sh --yes로 자동 생성 가능)"
    fi

    SUMMARY_DIR="$VAULT_BASE/Daily Summary"
    if [[ -d "$SUMMARY_DIR" ]]; then
        ok "Daily Summary 폴더 존재"
    else
        info "Daily Summary 폴더 없음 (요약 작성 시 자동 생성 시도)"
    fi

    hdr "cron 등록 상태"
    if crontab -l 2>/dev/null | grep -q "plaud-auto-recording"; then
        ok "PLAUD cron 항목 등록됨"
    else
        info "cron 미등록 — 'npm run register-cron' 으로 등록 가능"
    fi

    exit 0
fi

# ---------- 사용자 동의 ----------
if ! $ASSUME_YES; then
    hdr "다음 작업을 수행합니다"
    cat <<EOF
  1) 프로젝트 로컬에 npm install playwright (~ 200MB)
  2) Playwright Chromium 다운로드 (~ 200MB)
  3) Python venv 생성 (.venv/) + faster-whisper 설치 (~ 50MB)
  4) 디렉토리 준비 (input/, logs/, ~/PLAUD-Data, Vault 폴더)
  5) .env 생성 (없을 때만)
  6) 실행 권한 부여
EOF
    printf "계속하시겠습니까? [y/N] "
    read -r ans
    if [[ "$ans" != "y" && "$ans" != "Y" ]]; then
        err "취소했습니다."
        exit 1
    fi
fi

# ---------- 2. Node 의존성 ----------
hdr "2. Node.js 의존성"
if [[ ! -f package.json ]]; then
    warn "package.json이 없습니다. 자동 생성합니다."
    npm init -y >/dev/null
fi

if [[ ! -d node_modules/playwright ]]; then
    info "Node 의존성 설치 중..."
    npm install
    ok "의존성 설치 완료"
else
    ok "Node 의존성 이미 설치됨"
fi

info "Chromium 브라우저 확인/다운로드 중..."
npx --yes playwright install chromium
ok "Chromium 준비 완료"

# ---------- 3. Python 의존성 ----------
hdr "3. Python 의존성"

# faster-whisper(CTranslate2)는 Python 3.13까지 검증.
# 3.14 이상이면 brew의 python@3.11을 우선 시도.
PY_FOR_VENV="python3"
if [[ "$PY_MAJOR" -eq 3 ]] && [[ "$PY_MINOR" -ge 14 ]]; then
    warn "Python ${PY_VER}는 faster-whisper 호환성이 불안정합니다."
    if [[ -x /opt/homebrew/opt/python@3.11/bin/python3.11 ]]; then
        PY_FOR_VENV="/opt/homebrew/opt/python@3.11/bin/python3.11"
        ok "python@3.11 사용: $PY_FOR_VENV"
    elif [[ -x /usr/local/opt/python@3.11/bin/python3.11 ]]; then
        PY_FOR_VENV="/usr/local/opt/python@3.11/bin/python3.11"
        ok "python@3.11 사용: $PY_FOR_VENV"
    elif command -v python3.11 >/dev/null 2>&1; then
        PY_FOR_VENV="$(command -v python3.11)"
        ok "python3.11 사용: $PY_FOR_VENV"
    else
        warn "python@3.11을 찾지 못했습니다. faster-whisper 설치가 실패할 수 있습니다."
        info "권장: brew install python@3.11"
        if ! $ASSUME_YES; then
            printf "그래도 Python ${PY_VER}로 진행하시겠습니까? [y/N] "
            read -r ans2
            if [[ "$ans2" != "y" && "$ans2" != "Y" ]]; then
                err "취소했습니다. brew install python@3.11 후 다시 실행하세요."
                exit 1
            fi
        fi
    fi
fi

if [[ ! -d .venv ]]; then
    "$PY_FOR_VENV" -m venv .venv
    ok ".venv 생성 ($($PY_FOR_VENV --version))"
else
    VENV_VER="$(.venv/bin/python3 --version 2>&1 || true)"
    ok ".venv 존재 ($VENV_VER)"
fi

# pip 업그레이드 (조용히)
.venv/bin/pip install --upgrade pip >/dev/null
if .venv/bin/python3 -c "import faster_whisper" 2>/dev/null; then
    ok "faster-whisper 이미 설치됨"
else
    info "Python 의존성 설치 중..."
    if [[ -f requirements.txt ]]; then
        .venv/bin/pip install -r requirements.txt
    else
        .venv/bin/pip install faster-whisper
    fi
    ok "Python 의존성 설치 완료"
fi

# ---------- 4. 디렉토리 ----------
hdr "4. 디렉토리 준비"
mkdir -p input logs
ok "input/, logs/"

mkdir -p "$HOME/PLAUD-Data"
ok "~/PLAUD-Data"

if [[ -d "$VAULT_BASE" ]]; then
    mkdir -p "$VAULT_BASE/Transcripts" "$VAULT_BASE/Daily Summary"
    ok "Vault: Transcripts/, Daily Summary/"
else
    warn "Vault 경로가 없어 폴더 생성을 건너뜀: $VAULT_BASE"
fi

# ---------- 5. .env ----------
hdr "5. 환경 파일"
if [[ ! -f .env ]]; then
    cp .env.example .env
    ok ".env 생성 (.env.example에서 복사)"
    warn "에디터로 .env 를 열어 PLAUD_AUTH_MODE 와 자격증명을 확인하세요"
else
    ok ".env 존재 (덮어쓰지 않음)"
fi

# ---------- 6. 실행 권한 ----------
hdr "6. 실행 권한"
SKILL_SCRIPTS="$PROJECT_DIR/.claude/skills/plaud-pipeline/scripts"
chmod +x "$SKILL_SCRIPTS"/*.sh "$SKILL_SCRIPTS"/*.js "$SKILL_SCRIPTS"/*.py 2>/dev/null || true
chmod +x "$PROJECT_DIR/setup.sh" 2>/dev/null || true
ok "실행 권한 부여"

# ---------- 다음 단계 ----------
hdr "✨ 설치 완료"
cat <<EOF

  1) .env 파일에서 인증 모드 확인 (필요 시 편집):
     - PLAUD_AUTH_MODE=session   (구글 간편로그인)
     - PLAUD_AUTH_MODE=password  (이메일 + 비밀번호)

  2) [세션 모드] 첫 1회만 GUI에서 구글 로그인:
     node .claude/skills/plaud-pipeline/scripts/plaud_session_login.js --first-time

  3) 파이프라인 시험 실행:
     bash .claude/skills/plaud-pipeline/scripts/run_pipeline.sh

  4) 매일 자동 실행 (cron, 새벽 3시 예시):
     crontab -e
     0 3 * * * /bin/bash $PROJECT_DIR/.claude/skills/plaud-pipeline/scripts/run_pipeline.sh >> $PROJECT_DIR/logs/cron.log 2>&1

  점검만 다시 하려면: ./setup.sh --check

EOF
