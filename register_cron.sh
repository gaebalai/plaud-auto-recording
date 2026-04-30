#!/usr/bin/env bash
# crontab에 PLAUD 자동화 두 항목을 등록 (멱등).
#
# 사용법:
#   ./register_cron.sh             # 등록 또는 갱신 (백업 + 적용)
#   ./register_cron.sh --check     # 현재 등록 상태만 표시
#   ./register_cron.sh --dry-run   # 적용하지 않고 변경 미리보기
#   ./register_cron.sh --remove    # PLAUD 항목 제거 (다른 cron은 보존)
#   ./register_cron.sh --yes       # 확인 프롬프트 없이 자동 진행
#
# 환경변수로 시간 조정 가능:
#   PLAUD_CRON_TIME="0 3 * * *"        (기본: 매일 03:00 파이프라인)
#   PLAUD_HEALTH_CRON_TIME="0 9 * * 1" (기본: 매주 월 09:00 헬스체크)
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
DO_REMOVE=false
DO_DRY=false
DO_CHECK=false
ASSUME_YES=false
for arg in "$@"; do
    case "$arg" in
        --remove)  DO_REMOVE=true ;;
        --dry|--dry-run) DO_DRY=true ;;
        --check)   DO_CHECK=true ;;
        --yes|-y)  ASSUME_YES=true ;;
        -h|--help)
            sed -n '2,15p' "$0" | sed 's/^# *//'
            exit 0
            ;;
        *)
            err "알 수 없는 옵션: $arg"
            exit 1
            ;;
    esac
done

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$PROJECT_DIR/.claude/skills/plaud-pipeline/scripts"
LOG_DIR="$PROJECT_DIR/logs"
MARKER_PREFIX="# plaud-auto-recording"

PIPELINE_TIME="${PLAUD_CRON_TIME:-0 3 * * *}"
HEALTH_TIME="${PLAUD_HEALTH_CRON_TIME:-0 9 * * 1}"

# ---------- 현재 crontab 가져오기 ----------
CURRENT="$(crontab -l 2>/dev/null || true)"

# ---------- --check 모드 ----------
if $DO_CHECK; then
    hdr "현재 crontab의 PLAUD 항목"
    if echo "$CURRENT" | grep -q "$MARKER_PREFIX"; then
        echo "$CURRENT" | awk -v m="$MARKER_PREFIX" '
            $0 ~ m { mark=1 ; print ; next }
            mark   { print ; mark=0 ; next }
        '
    else
        warn "PLAUD 항목이 등록되어 있지 않습니다."
    fi
    exit 0
fi

# ---------- 기존 PLAUD 항목 필터링 (마커 + 다음 줄 1줄을 한 쌍으로 제거) ----------
FILTERED="$(echo "$CURRENT" | awk -v m="$MARKER_PREFIX" '
    BEGIN { skip = 0 }
    {
        if (skip > 0) { skip-- ; next }
        if ($0 ~ m)   { skip = 1 ; next }
        print
    }
')"

# ---------- 새 항목 ----------
NEW_ENTRIES="$MARKER_PREFIX (pipeline)
$PIPELINE_TIME /bin/bash $SCRIPT_DIR/run_pipeline.sh >> $LOG_DIR/cron.log 2>&1
$MARKER_PREFIX (health)
$HEALTH_TIME /bin/bash $SCRIPT_DIR/health_check.sh >> $LOG_DIR/health.log 2>&1"

# ---------- 최종 crontab 텍스트 구성 ----------
if $DO_REMOVE; then
    hdr "PLAUD 항목을 제거합니다"
    NEW_CRONTAB="$FILTERED"
else
    hdr "PLAUD 항목을 등록/갱신합니다"
    if [[ -n "$FILTERED" ]]; then
        NEW_CRONTAB="$FILTERED
$NEW_ENTRIES"
    else
        NEW_CRONTAB="$NEW_ENTRIES"
    fi
fi

# 끝에 줄바꿈 보장
if [[ -n "$NEW_CRONTAB" && "${NEW_CRONTAB: -1}" != $'\n' ]]; then
    NEW_CRONTAB="${NEW_CRONTAB}
"
fi

# ---------- 미리보기 ----------
echo "----- 변경 후 crontab 미리보기 -----"
if [[ -z "$NEW_CRONTAB" || "$NEW_CRONTAB" == $'\n' ]]; then
    echo "(비어있음)"
else
    printf '%s' "$NEW_CRONTAB"
fi
echo "------------------------------------"

if $DO_DRY; then
    info "(dry-run, 적용하지 않음)"
    exit 0
fi

# ---------- 사용자 동의 ----------
if ! $ASSUME_YES; then
    if $DO_REMOVE; then
        printf "PLAUD 항목을 제거하시겠습니까? [y/N] "
    else
        printf "이 내용으로 crontab을 갱신하시겠습니까? [y/N] "
    fi
    read -r ans
    if [[ "$ans" != "y" && "$ans" != "Y" ]]; then
        warn "취소했습니다."
        exit 1
    fi
fi

# ---------- 백업 ----------
mkdir -p "$LOG_DIR"
BACKUP_FILE="$LOG_DIR/crontab.backup.$(date +%Y%m%d-%H%M%S).txt"
if [[ -n "$CURRENT" ]]; then
    printf '%s\n' "$CURRENT" > "$BACKUP_FILE"
    ok "기존 crontab 백업: $BACKUP_FILE"
else
    : > "$BACKUP_FILE"
    info "기존 crontab이 비어 있었습니다 (백업: $BACKUP_FILE)"
fi

# ---------- 적용 ----------
printf '%s' "$NEW_CRONTAB" | crontab -
ok "crontab 갱신 완료"
info "확인: crontab -l"

# ---------- macOS Full Disk Access 안내 ----------
hdr "한 번만 수동으로 해주세요 — Full Disk Access"
cat <<EOF
cron이 iCloud Drive(Obsidian Vault)와 같은 보호 디렉토리에 접근하려면
시스템에서 cron에 'Full Disk Access' 권한을 부여해야 합니다.

  1) 시스템 설정 > 개인정보 보호 및 보안 > 전체 디스크 접근 권한
  2) '+' 버튼 클릭 → ⌘⇧G 입력 → /usr/sbin/cron 입력 → 추가
  3) 토글을 켭니다

  (또는 'bash' 인터프리터를 같은 절차로 추가해도 됩니다: /bin/bash)

이 권한이 없으면 cron이 조용히 Vault에 쓰지 못합니다.
권한 부여 후 처음 한 번은 './setup.sh --check' 또는 'npm run health'로 동작 확인을 권장합니다.

복구가 필요하면:
  crontab "$BACKUP_FILE"
EOF
