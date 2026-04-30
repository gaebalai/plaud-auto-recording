#!/usr/bin/env bash
# PLAUD 일일 파이프라인: 다운로드 → Whisper 음성 인식 → Vault 저장
#
# PLAUD_AUTH_MODE 환경변수로 인증 방식 선택:
#   - password (기본): 이메일 + 비밀번호 자동 로그인
#   - session         : Persistent Context 세션 재사용 (구글 간편로그인용)
#
# PLAUD_NOTIFY_ON_SUCCESS=1 로 설정하면 성공 시에도 macOS 알림 표시 (기본: 실패만 알림)
# PLAUD_LOG_RETENTION_DAYS=30 (기본) — 이 일수 이상 된 plaud_*.log / crontab.backup.* 자동 삭제
# PLAUD_LOG_TRUNCATE_BYTES=5242880 (기본 5MB) — cron.log/health.log가 이 크기 넘으면 마지막 5000줄만 보존
set -euo pipefail

# cron 환경에서는 PATH가 비어있을 수 있으므로 보강
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
NOTIFY_ON_SUCCESS="${PLAUD_NOTIFY_ON_SUCCESS:-0}"
LOG_RETENTION_DAYS="${PLAUD_LOG_RETENTION_DAYS:-30}"
LOG_TRUNCATE_BYTES="${PLAUD_LOG_TRUNCATE_BYTES:-5242880}"

INPUT_DIR="$PROJECT_DIR/input"
LOG_DIR="$PROJECT_DIR/logs"
TIMESTAMP="$(date '+%Y-%m-%d_%H%M')"
LOG_FILE="$LOG_DIR/plaud_${TIMESTAMP}.log"

mkdir -p "$INPUT_DIR" "$LOG_DIR"

log() { echo "$*" | tee -a "$LOG_FILE"; }

# macOS 알림센터 (osascript 없으면 조용히 무시)
notify() {
    local title="$1"
    local message="$2"
    local sound="${3:-Glass}"
    local safe_msg
    safe_msg="$(printf '%s' "$message" | sed 's/"/\\"/g')"
    osascript -e "display notification \"$safe_msg\" with title \"$title\" sound name \"$sound\"" 2>/dev/null || true
}

fail() {
    local msg="$1"
    log "오류: $msg"
    notify "PLAUD 파이프라인 실패" "$msg ($(basename "$LOG_FILE"))" "Basso"
    exit 1
}

# ---------------------------------------------------------
# 동시 실행 lock (mkdir은 atomic)
# ---------------------------------------------------------
LOCK_DIR="$LOG_DIR/.pipeline.lock"

acquire_lock() {
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        echo $$ > "$LOCK_DIR/pid"
        echo "$TIMESTAMP" > "$LOCK_DIR/since"
        return 0
    fi
    local owner_pid
    owner_pid="$(cat "$LOCK_DIR/pid" 2>/dev/null || echo "")"
    if [[ -n "$owner_pid" ]] && kill -0 "$owner_pid" 2>/dev/null; then
        return 1  # 정상 lock
    fi
    # stale lock — 정리하고 재취득
    log "오래된 lock 발견 (stale, owner_pid=$owner_pid). 정리하고 진행."
    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR"
    echo $$ > "$LOCK_DIR/pid"
    echo "$TIMESTAMP" > "$LOCK_DIR/since"
    return 0
}

if ! acquire_lock; then
    OWNER="$(cat "$LOCK_DIR/pid" 2>/dev/null || echo '?')"
    SINCE="$(cat "$LOCK_DIR/since" 2>/dev/null || echo '?')"
    log "이미 실행 중인 파이프라인이 있어 건너뜁니다. (PID=$OWNER, since=$SINCE)"
    notify "PLAUD 파이프라인 스킵" "이미 실행 중 (PID=$OWNER)" "Pop"
    exit 0
fi
trap 'rm -rf "$LOCK_DIR"' EXIT

PARTIAL=0

log "===== 시작: $TIMESTAMP (auth_mode=$AUTH_MODE, pid=$$) ====="

# ---------------------------------------------------------
# Preflight: Vault 쓰기 가능 여부 확인
# Whisper 인식이 다 끝난 뒤에 쓰기 실패하는 시나리오를 방지하기 위해
# 다운로드 시작 전 미리 검증한다.
# ---------------------------------------------------------
VAULT_OUTPUT="${PLAUD_OUTPUT_DIR:-$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/Transcripts}"
log "Vault 출력 경로: $VAULT_OUTPUT"

if [[ ! -d "$VAULT_OUTPUT" ]]; then
    if mkdir -p "$VAULT_OUTPUT" 2>>"$LOG_FILE"; then
        log "Vault 폴더 자동 생성: $VAULT_OUTPUT"
    else
        notify "PLAUD Vault 접근 실패" "경로 생성 불가 — 시스템 설정 > 전체 디스크 접근 확인" "Funk"
        fail "Vault 경로 생성 불가: $VAULT_OUTPUT"
    fi
fi

VAULT_TEST="$VAULT_OUTPUT/.plaud_write_test_$$"
if ! ( : > "$VAULT_TEST" ) 2>>"$LOG_FILE"; then
    notify "PLAUD Vault 쓰기 불가" "전체 디스크 접근 권한이 없을 수 있음" "Funk"
    fail "Vault 쓰기 권한 없음: $VAULT_OUTPUT"
fi
rm -f "$VAULT_TEST"
log "Vault 쓰기 권한 확인 OK"

# ---------------------------------------------------------
# 1단계: 다운로드 (인증 방식별 분기)
# 자격증명은 환경변수로 자식 프로세스에 상속 → ps에 노출되지 않음
# ---------------------------------------------------------
if [[ "$AUTH_MODE" == "token" ]]; then
    log "--- 1단계: 직접 토큰 모드 다운로드 ---"

    if [[ -z "${PLAUD_TOKEN:-}" ]]; then
        log "오류: .env에 PLAUD_TOKEN을 설정하세요."
        log "  Plaud Web에 평소처럼 로그인 후 개발자도구 > Application >"
        log "  Local Storage > tokenstr 값을 복사해 .env에 PLAUD_TOKEN= 으로 붙여넣기."
        notify "PLAUD 토큰 누락" ".env에 PLAUD_TOKEN을 설정하세요" "Funk"
        exit 1
    fi

    log "토큰 길이: ${#PLAUD_TOKEN}자 (preview: ${PLAUD_TOKEN:0:12}...)"

    DL_ARGS=(
        "$SCRIPT_DIR/plaud_download_audio.js"
        --download-dir "$INPUT_DIR"
        --verbose
    )
    [[ -n "${PLAUD_MOVE_TO_FOLDER_ID:-}" ]] && DL_ARGS+=(--move-to-folder-id "$PLAUD_MOVE_TO_FOLDER_ID")
    [[ -n "${PLAUD_API_BASE:-}" ]]          && DL_ARGS+=(--api-base "$PLAUD_API_BASE")

    # PLAUD_TOKEN은 env로 자식에 상속됨 (set -a로 source)
    node "${DL_ARGS[@]}" 2>&1 | tee -a "$LOG_FILE"
    DL_STATUS="${PIPESTATUS[0]}"
    if [[ "$DL_STATUS" -ne 0 && "$DL_STATUS" -ne 2 ]]; then
        # 401/403 같은 인증 실패라면 토큰 만료 가능성
        if grep -qE "401|403|토큰" "$LOG_FILE" 2>/dev/null; then
            notify "PLAUD 토큰 만료" "Plaud Web에서 새 tokenstr을 복사해 .env에 갱신" "Funk"
        fi
        fail "다운로드 실패 (exit=$DL_STATUS)"
    elif [[ "$DL_STATUS" -eq 2 ]]; then
        log "경고: 일부 파일 다운로드 실패 (exit=2). 계속 진행."
        PARTIAL=1
    fi
elif [[ "$AUTH_MODE" == "session" ]]; then
    log "--- 1-a: 세션에서 토큰 취득 (구글 로그인 모드) ---"

    SESSION_ARGS=("$SCRIPT_DIR/plaud_session_login.js" --headless --token-only)
    if [[ -n "${PLAUD_PROFILE_DIR:-}" ]]; then
        SESSION_ARGS+=(--profile-dir "$PLAUD_PROFILE_DIR")
    fi

    set +e
    PLAUD_TOKEN="$(node "${SESSION_ARGS[@]}" 2>>"$LOG_FILE")"
    SESS_STATUS=$?
    set -e

    if [[ "$SESS_STATUS" -ne 0 || -z "$PLAUD_TOKEN" ]]; then
        log "세션이 없거나 만료되었습니다."
        log "  복구: node $SCRIPT_DIR/plaud_session_login.js --first-time"
        notify "PLAUD 세션 만료" "GUI에서 구글 로그인을 한 번 다시 해주세요" "Funk"
        exit 1
    fi
    log "세션 토큰 취득 완료."

    log "--- 1-b: 다운로드 ---"
    DL_ARGS=(
        "$SCRIPT_DIR/plaud_download_audio.js"
        --token "$PLAUD_TOKEN"
        --download-dir "$INPUT_DIR"
        --verbose
    )
    [[ -n "${PLAUD_MOVE_TO_FOLDER_ID:-}" ]] && DL_ARGS+=(--move-to-folder-id "$PLAUD_MOVE_TO_FOLDER_ID")
    [[ -n "${PLAUD_API_BASE:-}" ]]          && DL_ARGS+=(--api-base "$PLAUD_API_BASE")

    node "${DL_ARGS[@]}" 2>&1 | tee -a "$LOG_FILE"
    DL_STATUS="${PIPESTATUS[0]}"
    if [[ "$DL_STATUS" -ne 0 && "$DL_STATUS" -ne 2 ]]; then
        fail "다운로드 실패 (exit=$DL_STATUS)"
    elif [[ "$DL_STATUS" -eq 2 ]]; then
        log "경고: 일부 파일 다운로드 실패 (exit=2). 계속 진행."
        PARTIAL=1
    fi
else
    log "--- 1단계: Plaud Web 비밀번호 로그인 후 다운로드 ---"

    if [[ -z "${PLAUD_EMAIL:-}" || -z "${PLAUD_PASSWORD:-}" ]]; then
        log "오류: .env에 PLAUD_EMAIL과 PLAUD_PASSWORD를 설정하세요."
        log "  cp .env.example .env  # 후 편집"
        log "(구글 간편로그인을 쓰신다면 PLAUD_AUTH_MODE=session 으로 전환)"
        notify "PLAUD 자격증명 누락" ".env 파일을 확인해 주세요" "Funk"
        exit 1
    fi

    # 자격증명은 인자가 아닌 환경변수로 전달 (set -a로 이미 export됨)
    NODE_ARGS=(
        "$SCRIPT_DIR/plaud_login_and_download.js"
        --download-dir "$INPUT_DIR"
        --verbose
    )
    [[ -n "${PLAUD_MOVE_TO_FOLDER_ID:-}" ]] && NODE_ARGS+=(--move-to-folder-id "$PLAUD_MOVE_TO_FOLDER_ID")
    [[ -n "${PLAUD_API_BASE:-}" ]]          && NODE_ARGS+=(--api-base "$PLAUD_API_BASE")
    [[ -n "${PLAUD_HEADLESS:-}" ]]          && NODE_ARGS+=(--headless)

    node "${NODE_ARGS[@]}" 2>&1 | tee -a "$LOG_FILE"
    DL_STATUS="${PIPESTATUS[0]}"
    if [[ "$DL_STATUS" -ne 0 && "$DL_STATUS" -ne 2 ]]; then
        fail "다운로드 실패 (exit=$DL_STATUS)"
    elif [[ "$DL_STATUS" -eq 2 ]]; then
        log "경고: 일부 파일 다운로드 실패 (exit=2). 계속 진행."
        PARTIAL=1
    fi
fi

# ---------------------------------------------------------
# 2단계: 음성 인식 (.venv가 있으면 우선 사용)
# ---------------------------------------------------------
log "--- 2단계: faster-whisper 음성 인식 ---"
if [[ -x "$PROJECT_DIR/.venv/bin/python3" ]]; then
    PY_BIN="$PROJECT_DIR/.venv/bin/python3"
else
    PY_BIN="python3"
fi
log "Python: $PY_BIN"

WHISPER_START="$(date +%s)"
"$PY_BIN" "$SCRIPT_DIR/whisper_transcribe.py" 2>&1 | tee -a "$LOG_FILE"
WHISPER_STATUS="${PIPESTATUS[0]}"
WHISPER_ELAPSED=$(( $(date +%s) - WHISPER_START ))
log "Whisper 처리 시간: ${WHISPER_ELAPSED}초"

if [[ "$WHISPER_STATUS" -ne 0 ]]; then
    # whisper_transcribe.py는 일부 파일만 실패해도 exit 1을 내지만,
    # 실패 파일은 input/failed/로 격리되므로 다음 실행은 영향 없음.
    log "경고: 음성 인식에서 일부 파일 실패 (exit=$WHISPER_STATUS). failed/로 격리됨."
    PARTIAL=1
fi

# ---------------------------------------------------------
# 마무리: 로그 회전 + 알림
# ---------------------------------------------------------
if [[ "$LOG_RETENTION_DAYS" -gt 0 ]]; then
    OLD_LOGS=$(find "$LOG_DIR" \
        \( -name "plaud_*.log" -o -name "crontab.backup.*.txt" \) \
        -mtime "+$LOG_RETENTION_DAYS" -print -delete 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$OLD_LOGS" -gt 0 ]]; then
        log "오래된 로그/백업 ${OLD_LOGS}개 정리 (${LOG_RETENTION_DAYS}일 이상)"
    fi
fi

# 누적 로그(cron.log, health.log) 크기 제한
for big_log in "$LOG_DIR/cron.log" "$LOG_DIR/health.log"; do
    if [[ -f "$big_log" ]]; then
        size=$(stat -f%z "$big_log" 2>/dev/null || echo 0)
        if [[ "$size" -gt "$LOG_TRUNCATE_BYTES" ]]; then
            tail -n 5000 "$big_log" > "$big_log.tmp" && mv "$big_log.tmp" "$big_log"
            log "$(basename "$big_log") truncated (was=${size}B → tail 5000줄)"
        fi
    fi
done

log "===== 종료: $(date '+%Y-%m-%d_%H%M') (partial=$PARTIAL) ====="
log "로그: $LOG_FILE"

if [[ "$PARTIAL" -eq 1 ]]; then
    notify "PLAUD 파이프라인 부분 실패" "일부 파일 처리 실패. 로그: $(basename "$LOG_FILE")" "Funk"
elif [[ "$NOTIFY_ON_SUCCESS" == "1" ]]; then
    notify "PLAUD 파이프라인 완료" "로그: $(basename "$LOG_FILE")" "Glass"
fi
