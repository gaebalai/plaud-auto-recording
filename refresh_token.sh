#!/usr/bin/env bash
# PLAUD 토큰만 빠르게 갱신 (만료 알림 받았을 때 사용)
#
# 사용법:
#   ./refresh_token.sh              # 인터랙티브 (클립보드 또는 직접 입력)
#   npm run refresh-token           # 위와 동일
#   ./refresh_token.sh <토큰>       # 토큰을 인자로 직접
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

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

if [[ ! -f .env ]]; then
    err ".env 파일이 없습니다."
    info "먼저 ./setup.sh 를 실행해 주세요."
    exit 1
fi

token="${1:-}"

if [[ -z "$token" ]]; then
    cat <<'PROMPT'

== PLAUD 토큰 갱신 ==

방법 1) 자동 — 콘솔 한 줄로 클립보드에 복사
  Chrome에서 https://web.plaud.ai 로그인 상태에서:
    a) ⌘⌥I → Console 탭
    b) 다음 한 줄을 콘솔에 붙여넣기 ('Allow pasting' 경고 시 허용):

PROMPT
    if [[ -f tools/extract-token.console.min.js ]]; then
        printf "  "
        cat tools/extract-token.console.min.js
    fi
    cat <<'PROMPT'

    c) 페이지 클릭 또는 새로고침 → 콘솔에 "✅ 토큰 클립보드 복사" 확인
    d) 여기로 돌아와서 Enter

방법 2) 북마클릿 — 이미 등록했으면 Plaud Web에서 클릭만
방법 3) 수동 — Network 탭의 authorization 헤더 직접 복사

PROMPT
    printf "클립보드의 토큰 사용하려면 Enter, 직접 입력하려면 토큰: "
    read -r token

    if [[ -z "$token" ]] && command -v pbpaste >/dev/null 2>&1; then
        token="$(pbpaste 2>/dev/null || true)"
        if [[ -n "$token" ]]; then
            info "클립보드에서 토큰을 받았습니다 (길이: ${#token}자)"
        fi
    fi
fi

# 정규화
token="$(printf '%s' "$token" | sed -E 's/^[[:space:]]*[Bb]earer[[:space:]]+//; s/^[[:space:]]+//; s/[[:space:]]+$//')"

if [[ -z "$token" ]]; then
    err "토큰이 비어있습니다. 갱신 취소."
    exit 1
fi

# 길이 점검 (대략 200자 미만은 의심)
if [[ "${#token}" -lt 100 ]]; then
    warn "토큰이 너무 짧습니다 (${#token}자). 잘못 복사된 것 같습니다."
    printf "그래도 진행할까요? [y/N] "
    read -r ans
    [[ "$ans" != "y" && "$ans" != "Y" ]] && { err "취소."; exit 1; }
fi

info "토큰 검증 중..."

# 두 API base 시도
VERIFIED_BASE=""
for base in "https://api-apne1.plaud.ai" "https://api.plaud.ai"; do
    status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
        -H "Authorization: Bearer $token" \
        -H "app-platform: web" \
        -H "Origin: https://web.plaud.ai" \
        -H "Referer: https://web.plaud.ai/" \
        "$base/file/simple/web?skip=0&limit=1&is_trash=0&categoryId=unorganized" 2>/dev/null || echo "000")
    if [[ "$status" == "200" ]]; then
        VERIFIED_BASE="$base"
        break
    fi
done

if [[ -z "$VERIFIED_BASE" ]]; then
    warn "토큰 검증 실패 (두 API 모두 거부). 그래도 .env에 저장합니다."
    warn "  - 토큰을 다시 받아주세요 (Chrome 로그아웃 → 재로그인 후 새 토큰)"
    VERIFIED_BASE="https://api-apne1.plaud.ai"
fi

# .env 갱신 — 멱등 (기존 라인 제거 후 추가)
sed -i '' '/^PLAUD_TOKEN=/d' .env
sed -i '' '/^PLAUD_API_BASE=/d' .env
sed -i '' '/^PLAUD_AUTH_MODE=/d' .env

{
    echo "PLAUD_AUTH_MODE=token"
    echo "PLAUD_TOKEN=$token"
    echo "PLAUD_API_BASE=$VERIFIED_BASE"
    echo ""
} >> .env

# (이미 다른 항목이 있다면 위에 sed로 제거되었으므로 충돌 없음)

chmod 600 .env

ok "토큰 갱신 완료"
info "  AUTH_MODE: token"
info "  API_BASE:  $VERIFIED_BASE"
info "  TOKEN:     ${token:0:12}...${token: -10} (${#token}자)"
echo ""
info "다음 실행: npm run pipeline"
