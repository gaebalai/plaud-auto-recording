---
name: plaud-pipeline
description: PLAUD NotePin 녹음을 Plaud Web에서 자동 수집하고 로컬 faster-whisper로 음성 인식해 Obsidian Vault의 날짜별 Markdown에 저장하는 파이프라인. 사용자가 "plaud 가져와", "오늘 녹음 정리해줘", "녹음 처리해", "/plaud-daily" 같은 요청을 하면 발동. macOS 전용.
---

# PLAUD 자동 수집 파이프라인

PLAUD NotePin → Plaud Web → 로컬 다운로드 → faster-whisper 음성 인식 → Obsidian Vault 저장의 전체 흐름을 자동화한다.

## 발동 조건

다음과 같은 사용자 요청에서 자동 활성화:
- "PLAUD 녹음 가져와줘" / "오늘 녹음 처리해" / "Plaud 수집 돌려"
- 슬래시 커맨드 `/plaud-daily`
- 서브에이전트 `plaud-collector`로부터의 위임

## 최초 설치 (한 번만)

```bash
cd ${CLAUDE_PROJECT_DIR}
./setup.sh           # 의존성 설치 + 디렉토리 준비
./setup.sh --check   # 점검만 (변경 없음)
./setup.sh --yes     # 확인 없이 자동 진행
```

`setup.sh`가 자동으로 처리:
- Node.js / Python / Homebrew 점검 (없으면 설치 명령 안내)
- `npm install playwright` + Chromium 다운로드
- Python `.venv` 생성 + `faster-whisper` 설치
- `input/`, `logs/`, `~/PLAUD-Data/`, Vault 폴더 생성
- `.env` 자동 생성 (없을 때만)
- 스크립트 실행 권한 부여

만약 설치 후 동작이 의심스러우면 `./setup.sh --check`로 상태만 다시 점검 가능.

## 파이프라인 단계

1. **로그인 및 토큰 취득** — Playwright로 Plaud Web 로그인, localStorage에서 인증 토큰 추출
2. **녹음 다운로드** — "미분류" 폴더의 음성 파일을 `input/`에 받고, 처리 후 Plaud Web의 다른 폴더로 이동(중복 방지)
3. **로컬 음성 인식** — faster-whisper(`large-v3-turbo`, 한국어, CPU `int8`)로 transcribe
4. **날짜별 Markdown 저장** — `[HH:MM:SS] 발화` 형식으로 Obsidian Vault의 `Transcripts/YYYY-MM-DD.md`에 추가 기입
5. **원본 음성 아카이브** — 처리된 음성을 `~/PLAUD-Data/`로 이동

## 실행 방법

전체 파이프라인 한 번에:
```bash
bash ${CLAUDE_PROJECT_DIR}/.claude/skills/plaud-pipeline/scripts/run_pipeline.sh
```

개별 단계만:
- 다운로드만: `node ${CLAUDE_PROJECT_DIR}/.claude/skills/plaud-pipeline/scripts/plaud_login_and_download.js --email "$PLAUD_EMAIL" --password "$PLAUD_PASSWORD" --download-dir "${CLAUDE_PROJECT_DIR}/input"`
- 음성 인식만: `python3 ${CLAUDE_PROJECT_DIR}/.claude/skills/plaud-pipeline/scripts/whisper_transcribe.py`

## 환경 변수 (`.env`)

프로젝트 루트의 `.env` 파일에 정의 (`.env.example` 참고):
- `PLAUD_AUTH_MODE` — `password`(기본) / `session`(구글 OAuth 자동) / `token`(수동 토큰)
- `PLAUD_EMAIL`, `PLAUD_PASSWORD` — password 모드일 때만 필요
- `PLAUD_TOKEN` — token 모드일 때만 필요. Plaud Web 로그인 후 개발자도구의 `localStorage.tokenstr` 값
- `PLAUD_PROFILE_DIR` — session 모드 프로필 위치(기본 `~/.plaud-pipeline-profile`)
- `PLAUD_MOVE_TO_FOLDER_ID` — 다운로드 후 옮길 Plaud Web 폴더 ID(선택). Plaud Web URL의 `tagId=` 뒤 값
- `PLAUD_API_BASE` — `https://api-apne1.plaud.ai`(기본) 또는 `https://api.plaud.ai`로 fallback

## 인증 모드 선택 가이드

| 상황 | 권장 모드 | 메모 |
|---|---|---|
| Plaud에 비밀번호 추가 가능 | `password` | 가장 안정. 무인 cron 100% |
| 구글 OAuth만 가능 + Playwright로 통과됨 | `session` | 자동 갱신 안 됨, 수 주마다 GUI 재로그인 |
| 구글 OAuth만 가능 + Playwright 차단됨 | `token` | 본인 Chrome에서 토큰 복사. 만료 시 갱신 |

## 구글 간편로그인 모드 사용법 (session)

Plaud 계정이 구글 OAuth만 쓰는 경우:

1. `.env`에서 `PLAUD_AUTH_MODE=session` 설정
2. **첫 실행 1회**(반드시 GUI 환경):
   ```bash
   node ./.claude/skills/plaud-pipeline/scripts/plaud_session_login.js --first-time
   ```
   브라우저가 떠서 구글 로그인을 직접 완료. 토큰이 추출되면 자동 종료. 세션은 `~/.plaud-pipeline-profile/`에 저장됨
3. 이후 `run_pipeline.sh`는 `--headless --token-only`로 그 세션을 재사용해 토큰만 추출
4. **세션 만료 시(보통 수 주 후)** — 자동 실행이 "세션이 없거나 만료되었습니다"로 실패. 위 1단계 명령을 다시 한 번 GUI에서 실행

세션 프로필에는 사용자의 구글 쿠키가 들어 있으므로 절대 git에 올리거나 공유하지 말 것.

Whisper 동작 조정(선택):
- `WHISPER_MODEL` — 기본 `large-v3-turbo`. 더 빠르게는 `medium`, `small`
- `WHISPER_DEVICE` — 기본 `cpu`. faster-whisper는 macOS에서 mps 미지원
- `WHISPER_COMPUTE_TYPE` — 기본 `int8`

경로 override(선택):
- `PLAUD_INPUT_DIR`, `PLAUD_PROCESSED_DIR`, `PLAUD_OUTPUT_DIR`

## 기본 경로 약속

| 용도 | 경로 |
|---|---|
| 임시 다운로드 | `${CLAUDE_PROJECT_DIR}/input/` |
| 처리 완료 음성 | `~/PLAUD-Data/` |
| 인식 텍스트(Vault) | `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Transcripts/YYYY-MM-DD.md` |
| 요약(Vault) | `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Daily Summary/YYYY-MM-DD_summary.md` |
| 실행 로그 | `${CLAUDE_PROJECT_DIR}/logs/plaud_*.log` |

## 자주 마주치는 문제

- **"토큰을 찾을 수 없습니다"** — Plaud Web 로그인 화면 셀렉터가 바뀐 것. `scripts/plaud_login_and_download.js`의 `input[placeholder="이메일 주소"]` 셀렉터를 현재 화면에 맞게 조정
- **다운로드 응답 401/403** — 토큰 만료. 재실행 시 자동 재로그인됨
- **API 연결 실패** — `PLAUD_API_BASE`를 `https://api.plaud.ai`로 변경 시도
- **첫 실행 시 모델 다운로드가 길다** — `large-v3-turbo`는 약 1.5GB. 한 번 받으면 `~/.cache/huggingface/`에 캐시됨
- **"파일명 형식 오류"** — Plaud 파일명이 `YYYY-MM-DD HH_MM_SS.mp3` 패턴이어야 함. 다른 패턴은 `whisper_transcribe.py`의 `parse_start_dt()` 보강 필요

## 후속 처리

날짜별 `.md`가 생긴 뒤 그날치 ADHD 친화 요약을 만들고 싶으면:
- `plaud-collector` 서브에이전트 호출, 또는
- `templates/daily_summary.md`의 프롬프트를 사용해 직접 요약

## 자동화 (cron 자동 등록)

```bash
npm run register-cron:dry    # 변경 미리보기 (적용 안 함)
npm run register-cron        # 적용 (백업 + 멱등 갱신)
npm run register-cron:check  # 등록 상태만 확인
npm run uncron               # PLAUD 항목 제거 (다른 cron은 보존)
```

기본 등록되는 두 항목:
- 매일 03:00 — `run_pipeline.sh` 실행 → `logs/cron.log`
- 매주 월요일 09:00 — `health_check.sh` 실행 → `logs/health.log`

시간을 바꾸려면 환경변수로:
```bash
PLAUD_CRON_TIME="0 4 * * *" PLAUD_HEALTH_CRON_TIME="0 8 * * 1" npm run register-cron
```

`register_cron.sh`는:
- 기존 crontab을 `logs/crontab.backup.YYYYMMDD-HHMM.txt`로 자동 백업
- PLAUD 마커가 있는 줄과 다음 줄을 한 쌍으로 제거 후 새 항목 추가 (멱등)
- 다른 cron 항목은 그대로 유지

### ⚠ macOS Full Disk Access (한 번만 수동)

cron이 iCloud Drive(Obsidian Vault)에 쓰려면 시스템 권한이 필요합니다:
1. 시스템 설정 > 개인정보 보호 및 보안 > 전체 디스크 접근 권한
2. `+` → `⌘⇧G` → `/usr/sbin/cron` 추가 후 토글 켜기

이 권한이 없으면 cron 실행은 되지만 Vault에 못 씁니다(파이프라인은 성공으로 보이는데 Transcripts가 안 생김).

수동 헬스체크: `npm run health`

## 안전 수칙

- `.env`는 절대 git에 커밋 금지(`.gitignore`에 포함됨)
- 자격증명을 로그에 출력하지 않음
- 처리 완료 음성 자동 삭제 금지(필요 시 사용자 확인 후)
