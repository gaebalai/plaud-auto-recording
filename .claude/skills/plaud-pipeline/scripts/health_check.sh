#!/usr/bin/env bash
# 세션 헬스체크: PLAUD_AUTH_MODE=session 일 때, 저장된 브라우저 세션이 살아있는지 확인.
# 토큰 추출 실패 시 macOS 알림센터로 통지.
#
# 권장 사용법: 주 1회 cron 등록
#   crontab -e
#   0 9 * * 1 /bin/bash /Users/.../.claude/skills/plaud-pipeline/scripts/health_check.sh >> /Users/.../logs/health.log 2>&1
#
# 종료 코드:
#   0 — 세션 정상 또는 password 모드라 체크 불필요
#   1 — 세션 만료/실패. 사용자 GUI 로그인 필요
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_DIR="$(cd "$SKILL_DIR/../../.." && pwd)"

if [[ -f "$PROJECT_DIR/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$PROJECT_DIR/.env"
    set +a
fi

AUTH_MODE="${PLAUD_AUTH_MODE:-password}"

notify() {
    local title="$1"
    local message="$2"
    local sound="${3:-Glass}"
    local safe_msg
    safe_msg="$(printf '%s' "$message" | sed 's/"/\\"/g')"
    osascript -e "display notification \"$safe_msg\" with title \"$title\" sound name \"$sound\"" 2>/dev/null || true
}

TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"

if [[ "$AUTH_MODE" == "password" ]]; then
    echo "[$TIMESTAMP] auth_mode=password → 헬스체크 불필요 (매번 새로 로그인)"
    exit 0
elif [[ "$AUTH_MODE" == "token" ]]; then
    echo "[$TIMESTAMP] auth_mode=token → 토큰 존재 여부만 확인..."
    if [[ -z "${PLAUD_TOKEN:-}" ]]; then
        echo "[$TIMESTAMP] ✗ PLAUD_TOKEN이 .env에 없습니다."
        notify "PLAUD 토큰 누락" ".env에 PLAUD_TOKEN을 설정해 주세요" "Funk"
        exit 1
    fi
    # 실제 만료 여부는 다음 파이프라인 실행 시 401/403으로 검출됨
    echo "[$TIMESTAMP] ✓ PLAUD_TOKEN 설정됨 (preview: ${PLAUD_TOKEN:0:12}...)"
    echo "  실제 만료는 다음 다운로드 시 검출됩니다."
    exit 0
fi
# 이하 session 모드

echo "[$TIMESTAMP] 세션 헬스체크 시작..."

SESSION_ARGS=("$SCRIPT_DIR/plaud_session_login.js" --headless --token-only)
if [[ -n "${PLAUD_PROFILE_DIR:-}" ]]; then
    SESSION_ARGS+=(--profile-dir "$PLAUD_PROFILE_DIR")
fi

set +e
TOKEN="$(node "${SESSION_ARGS[@]}" 2>&1)"
STATUS=$?
set -e

if [[ "$STATUS" -ne 0 || -z "$TOKEN" ]]; then
    echo "[$TIMESTAMP] ✗ 세션 만료 또는 추출 실패 (exit=$STATUS)"
    echo "----- 출력 -----"
    echo "$TOKEN"
    echo "---------------"
    notify "PLAUD 세션 만료 임박" "GUI에서 구글 로그인 1회 필요 — npm run first-login" "Funk"
    exit 1
fi

# 토큰 길이만 표시 (보안)
TOKEN_PREVIEW="${TOKEN:0:12}..."
echo "[$TIMESTAMP] ✓ 세션 정상 (token=$TOKEN_PREVIEW)"
exit 0
