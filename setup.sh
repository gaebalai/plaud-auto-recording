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
VERIFIED_API_BASE=""

# ---------- 인증 설정 헬퍼 함수 ----------

# 토큰 유효성 + 어떤 API base가 동작하는지 확인
verify_plaud_token() {
    local token="$1"
    local status
    for base in "https://api.plaud.ai" "https://api-apne1.plaud.ai"; do
        status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
            -H "Authorization: Bearer $token" \
            -H "app-platform: web" \
            -H "Origin: https://web.plaud.ai" \
            -H "Referer: https://web.plaud.ai/" \
            "$base/file/simple/web?skip=0&limit=1&is_trash=0" 2>/dev/null || echo "000")
        if [[ "$status" == "200" ]]; then
            VERIFIED_API_BASE="$base"
            return 0
        fi
    done
    return 1
}

_write_env_file() {
    # 인수: AUTH_MODE [추가 줄들...]
    local auth_mode="$1"; shift
    {
        echo "PLAUD_AUTH_MODE=$auth_mode"
        for line in "$@"; do
            echo "$line"
        done
    } > "$PROJECT_DIR/.env"
    chmod 600 "$PROJECT_DIR/.env"
}

_configure_password_mode() {
    printf "PLAUD 이메일: "
    read -r email
    printf "PLAUD 비밀번호: "
    read -rs password
    echo ""
    if [[ -z "$email" || -z "$password" ]]; then
        cp .env.example .env
        chmod 600 .env
        warn "이메일/비밀번호가 비어 있어 .env 템플릿만 생성. 직접 편집해 주세요."
        return
    fi
    _write_env_file "password" "PLAUD_EMAIL=$email" "PLAUD_PASSWORD=$password"
    ok ".env 작성 완료 (password 모드)"
}

_configure_token_mode() {
    cat <<'PROMPT'

== 토큰 받아오기 (5분) ==

  1) 본인 Chrome 또는 Brave에서 https://web.plaud.ai 접속
  2) 평소처럼 구글로 로그인
  3) ⌘⌥I (개발자 도구) 열기 → 상단 'Application' 탭
  4) 왼쪽 트리: Storage → Local Storage → https://web.plaud.ai
  5) 'tokenstr' (또는 'token', 'access_token') 키의 Value를 통째로 복사
     (eyJhbGc... 로 시작하는 200~400자 긴 문자열)

PROMPT
    printf "토큰을 붙여넣으세요 (빈 값 = 나중에 직접 편집): "
    read -r token

    if [[ -z "$token" ]]; then
        cp .env.example .env
        chmod 600 .env
        info ".env 템플릿이 생성되었습니다. 토큰은 나중에 PLAUD_TOKEN= 라인에 입력하세요."
        return
    fi

    info "토큰 검증 중... (Plaud API 호출)"
    if verify_plaud_token "$token"; then
        ok "토큰 인증 성공 (API: $VERIFIED_API_BASE)"
        _write_env_file "token" "PLAUD_TOKEN=$token" "PLAUD_API_BASE=$VERIFIED_API_BASE"
        ok ".env 작성 완료 (token 모드, chmod 600)"
    else
        warn "토큰 검증 실패. 401 또는 네트워크 문제."
        warn "  - 토큰을 다시 복사해서 PLAUD_TOKEN= 라인에 갱신"
        warn "  - 또는 PLAUD_API_BASE 를 변경 시도"
        _write_env_file "token" "PLAUD_TOKEN=$token" "PLAUD_API_BASE=https://api.plaud.ai"
        ok ".env는 일단 작성됨 (검증 실패해도 보존, 직접 갱신하세요)"
    fi
}

_configure_session_mode() {
    cp .env.example .env
    chmod 600 .env
    # 기본 password를 session으로 변경
    sed -i '' 's|^PLAUD_AUTH_MODE=password|PLAUD_AUTH_MODE=session|' .env
    ok ".env 작성 완료 (session 모드)"
    warn "구글 OAuth 자동 로그인은 자주 차단됩니다."
    info "첫 실행: npm run first-login (브라우저 떠서 직접 구글 로그인)"
    info "차단되면 './setup.sh' 다시 → 옵션 2(token 모드)로 전환하세요."
}

configure_env_interactive() {
    if $ASSUME_YES; then
        cp .env.example .env
        chmod 600 .env
        info "비대화형 모드: .env 템플릿만 생성. 직접 편집하세요."
        return
    fi

    cat <<'MENU'

Plaud 계정 인증 방식:
  1) 비밀번호 (Plaud Web에서 비밀번호 설정 가능한 경우)
  2) 토큰 직접 입력 (구글 OAuth 단독 / 자동화 차단된 경우) ⭐ 권장
  3) 구글 OAuth 자동 로그인 (자주 차단됨)
  s) 일단 템플릿만, 나중에 직접 편집

MENU
    printf "선택 [1/2/3/s, 기본=2]: "
    read -r mode_choice
    case "${mode_choice:-2}" in
        1) _configure_password_mode ;;
        2) _configure_token_mode ;;
        3) _configure_session_mode ;;
        *)
            cp .env.example .env
            chmod 600 .env
            info ".env 템플릿이 생성되었습니다. 직접 편집해 주세요."
            ;;
    esac
}

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
  5) Plaud 인증 정보 입력 (.env)
  6) 실행 권한 부여

⏱ 의존성 설치(약 5~10분) 동안 미리 토큰을 받아두면 시간 절약됩니다.
   가장 안정적인 token 모드:
     • https://web.plaud.ai 로그인 (본인 Chrome)
     • 개발자도구(⌘⌥I) → Application → Local Storage → tokenstr 복사
   (Plaud에 비밀번호를 설정해두셨다면 password 모드도 가능합니다)
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

find_python311() {
    if [[ -x /opt/homebrew/opt/python@3.11/bin/python3.11 ]]; then
        echo "/opt/homebrew/opt/python@3.11/bin/python3.11"
    elif [[ -x /usr/local/opt/python@3.11/bin/python3.11 ]]; then
        echo "/usr/local/opt/python@3.11/bin/python3.11"
    elif command -v python3.11 >/dev/null 2>&1; then
        command -v python3.11
    else
        echo ""
    fi
}

if [[ "$PY_MAJOR" -eq 3 ]] && [[ "$PY_MINOR" -ge 14 ]]; then
    warn "Python ${PY_VER}는 faster-whisper 호환성이 불안정합니다."

    # 1) 이미 설치된 python@3.11 탐색
    PY311="$(find_python311)"

    # 2) 없으면 brew로 자동 설치 시도
    if [[ -z "$PY311" && "$HAS_BREW" == "true" ]]; then
        DO_BREW=false
        if $ASSUME_YES; then
            DO_BREW=true
            info "--yes 모드: python@3.11을 자동으로 설치합니다 (5~10분 소요)"
        else
            printf "Homebrew로 python@3.11을 자동 설치할까요? (5~10분 소요) [y/N] "
            read -r ans3
            [[ "$ans3" == "y" || "$ans3" == "Y" ]] && DO_BREW=true
        fi

        if $DO_BREW; then
            info "brew install python@3.11 실행 중..."
            if brew install python@3.11; then
                ok "python@3.11 설치 완료"
                PY311="$(find_python311)"
            else
                err "brew install python@3.11 실패"
                exit 1
            fi
        fi
    fi

    # 3) python@3.11 사용 가능하면 적용
    if [[ -n "$PY311" ]]; then
        PY_FOR_VENV="$PY311"
        ok "python@3.11 사용: $PY_FOR_VENV"
    else
        # 4) 그래도 없으면 3.14로 진행할지 사용자 확인
        warn "python@3.11이 없습니다. faster-whisper 설치가 실패할 수 있습니다."
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

# ---------- 5. .env (인터랙티브 인증 설정) ----------
hdr "5. Plaud 인증 정보 (.env)"
if [[ -f .env ]]; then
    ok ".env 이미 존재 (덮어쓰지 않음)"
    info "변경하려면 직접 편집하거나 .env 삭제 후 setup 재실행"
else
    configure_env_interactive
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
