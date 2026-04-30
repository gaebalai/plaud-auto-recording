#!/usr/bin/env bash
# PLAUD 파이프라인 부트스트랩 (curl-pipe-bash 패턴)
#
# 원격 한 줄 사용:
#   curl -fsSL https://raw.githubusercontent.com/USER/REPO/main/bootstrap.sh | bash -s -- [디렉토리] [--auto]
#
# 로컬 사용:
#   bash bootstrap.sh [디렉토리] [--auto]
#
# 환경변수:
#   PLAUD_REPO    GitHub repo (기본: gaebalai/plaud-auto-recording)
#   PLAUD_BRANCH  브랜치 (기본: main)
#
# 옵션:
#   --auto        ./setup.sh --yes를 자동 실행 (확인 프롬프트 없음)
#   --no-setup    복제만 하고 setup.sh는 사용자가 직접
set -euo pipefail

# ---------- 색상 ----------
if [[ -t 1 ]]; then
    GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'
    BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'
else
    GREEN=''; YELLOW=''; RED=''; BLUE=''; BOLD=''; RESET=''
fi
ok()   { printf "${GREEN}✓${RESET} %s\n" "$*"; }
info() { printf "${BLUE}▸${RESET} %s\n" "$*"; }
warn() { printf "${YELLOW}⚠${RESET} %s\n" "$*"; }
err()  { printf "${RED}✗${RESET} %s\n" "$*" >&2; }

# ---------- 인수 ----------
REPO="${PLAUD_REPO:-gaebalai/plaud-auto-recording}"
BRANCH="${PLAUD_BRANCH:-main}"

TARGET=""
DO_AUTO=false
SKIP_SETUP=false
for arg in "$@"; do
    case "$arg" in
        --auto)     DO_AUTO=true ;;
        --no-setup) SKIP_SETUP=true ;;
        -h|--help)
            sed -n '2,15p' "$0" | sed 's/^# *//'
            exit 0
            ;;
        *)
            if [[ -z "$TARGET" && ! "$arg" =~ ^- ]]; then
                TARGET="$arg"
            fi
            ;;
    esac
done

[[ -z "$TARGET" ]] && TARGET="plaud-auto-recording"

# ---------- 사전 점검 ----------
if [[ "$(uname)" != "Darwin" ]]; then
    err "이 프로젝트는 macOS 전용입니다. (현재: $(uname))"
    exit 1
fi

if ! command -v node >/dev/null 2>&1; then
    err "Node.js가 필요합니다."
    info "설치: brew install node"
    exit 1
fi

if [[ -e "$TARGET" ]]; then
    err "$TARGET 이 이미 존재합니다."
    info "다른 이름을 인수로 주세요: bash bootstrap.sh my-pipeline"
    exit 1
fi

# ---------- repo 복제 ----------
info "$REPO#$BRANCH → $TARGET 복제 중..."
npx --yes tiged "$REPO#$BRANCH" "$TARGET"
ok "복제 완료"

# 실행 권한
chmod +x "$TARGET/setup.sh" "$TARGET/register_cron.sh" 2>/dev/null || true
chmod +x "$TARGET"/.claude/skills/plaud-pipeline/scripts/*.sh 2>/dev/null || true
chmod +x "$TARGET"/.claude/skills/plaud-pipeline/scripts/*.js 2>/dev/null || true
chmod +x "$TARGET"/.claude/skills/plaud-pipeline/scripts/*.py 2>/dev/null || true

if $SKIP_SETUP; then
    echo ""
    info "다음 단계:"
    echo "  cd $TARGET"
    echo "  ./setup.sh"
    exit 0
fi

# ---------- setup.sh 실행 ----------
echo ""
if $DO_AUTO; then
    info "./setup.sh --yes 자동 실행..."
    cd "$TARGET"
    bash setup.sh --yes
else
    info "./setup.sh 실행 (확인 프롬프트 1회)..."
    cd "$TARGET"
    bash setup.sh
fi

echo ""
ok "부트스트랩 완료"
echo ""
info "다음 단계:"
echo "  cd $TARGET"
echo "  # .env 편집 (PLAUD_AUTH_MODE, 자격증명)"
echo "  npm run first-login    # session 모드일 때"
echo "  npm run pipeline       # 시험 실행"
echo "  npm run register-cron  # cron 자동 등록"
