# PLAUD Auto Recording

PLAUD NotePin 녹음을 **완전 자동으로** 수집하고, 로컬 Whisper로 음성 인식해서 Obsidian Vault에 날짜별 Markdown으로 쌓는 파이프라인. macOS + Claude Code 환경에 맞춰 설계되었다.

생활 로그 용도로 PLAUD를 쓰면서 정작 데이터가 자산으로 쌓이지 않는 문제를 해결한다.

```
PLAUD NotePin
   → Plaud Web 자동 동기화
      → Playwright로 자동 다운로드 (이메일/비밀번호 또는 구글 OAuth)
         → faster-whisper 로컬 음성 인식 (한국어, large-v3-turbo)
            → Obsidian Vault `Transcripts/YYYY-MM-DD.md`
               → (선택) ADHD 친화 일일 요약
```

## 주요 기능

- **두 가지 인증 방식** — 이메일/비밀번호(`password`) 또는 구글 OAuth(`session`, Persistent Context)
- **로컬 음성 인식** — faster-whisper, 분당 과금 없음, 원문 영구 보존
- **운영 안정성**
  - 동시 실행 lock (사용자 수동 + cron 충돌 방지)
  - 다운로드 1회 자동 재시도
  - 부분 실패 시 macOS 알림센터로 통지
  - 인식 실패 파일 자동 격리 (`input/failed/`)
  - 로그 자동 회전 (30일 보관, 단일 누적 로그 5MB 제한)
  - Vault 쓰기 권한 사전 검증
- **자동화**
  - cron 두 줄 자동 등록 (백업·멱등·dry-run)
  - 매주 세션 헬스체크 (구글 모드)
- **Claude Code 통합**
  - Skill (`plaud-pipeline`) — 자연어로 "오늘 plaud 가져와" 같은 발화로 발동
  - 슬래시 커맨드 `/plaud-daily`
  - 서브에이전트 `plaud-collector` — 결과 검증·요약 작성

## 빠른 시작

### 사전 요구사항
- macOS (Apple Silicon 또는 Intel)
- Node.js 18+ (`brew install node`)
- Python 3.10+ (`brew install python@3.11` 권장. 3.14는 faster-whisper 호환성 불안정)
- Obsidian (Vault 한 개)
- PLAUD 계정

### 설치 (한 번) — 세 가지 방법 중 편한 걸로

#### 옵션 A — `npx` 한 줄 ⭐ 가장 매끄러움

```bash
npx create-plaud-pipeline my-recording
# 또는: npm create plaud-pipeline my-recording
cd my-recording
```

[`create-plaud-pipeline`](https://www.npmjs.com/package/create-plaud-pipeline) 패키지가 GitHub에서 최신 코드를 받아 `my-recording/`에 풀고, 곧장 `setup.sh`까지 자동 실행한다.

옵션:
```bash
npx create-plaud-pipeline my-recording --auto       # 확인 프롬프트 없이 자동
npx create-plaud-pipeline my-recording --no-setup   # 복제만, setup은 수동
```

#### 옵션 B — `curl | bash` 한 줄

```bash
curl -fsSL https://raw.githubusercontent.com/gaebalai/plaud-auto-recording/main/bootstrap.sh \
  | bash -s -- my-recording
```

`bootstrap.sh`가 [tiged](https://github.com/tiged/tiged)로 repo를 받고 `setup.sh`를 자동 실행. npm 의존성 없이 동작.

#### 옵션 C — 일반 git clone

```bash
git clone https://github.com/gaebalai/plaud-auto-recording.git
cd plaud-auto-recording
./setup.sh
```

`.env` 편집:
```bash
PLAUD_AUTH_MODE=session                 # 또는 password
# password 모드일 때만:
# PLAUD_EMAIL=your@email.com
# PLAUD_PASSWORD=your-password
```

### 첫 실행

**구글 로그인 모드 (`session`)**: 브라우저가 떠서 직접 로그인하면 세션이 저장된다.
```bash
npm run first-login
```

**시험 실행:**
```bash
npm run pipeline
```

### 자동화 (cron)

```bash
npm run register-cron                   # 매일 03:00 + 매주 월 09:00 헬스체크
```

추가로 한 번만 시스템 설정:
1. **시스템 설정 → 개인정보 보호 및 보안 → 전체 디스크 접근 권한**
2. `+` → `⌘⇧G` → `/usr/sbin/cron` 추가 후 토글 켜기

이게 빠지면 cron이 iCloud Drive(Vault)에 쓰지 못한다.

### 점검

```bash
npm run check                           # 한눈에 전체 상태
```

## 폴더 구조

```
plaud-auto-recording/
├─ setup.sh                             # 자동 설치 (Python 3.11 fallback 포함)
├─ register_cron.sh                     # cron 자동 등록 (백업/멱등)
├─ package.json                         # Node 의존성 + npm scripts
├─ requirements.txt                     # Python 의존성
├─ .env.example                         # 환경변수 템플릿
├─ README.md
├─ SCENARIOS.md                         # 상황별 운영 시나리오
├─ LICENSE                              # MIT
├─ plaude.md                            # 원본 가이드 (참고용)
├─ .claude/
│  ├─ skills/plaud-pipeline/
│  │  ├─ SKILL.md                       # Claude Code 스킬 정의
│  │  ├─ scripts/
│  │  │  ├─ run_pipeline.sh             # 메인 파이프라인
│  │  │  ├─ plaud_login_and_download.js # password 모드 로그인 + 다운로드
│  │  │  ├─ plaud_session_login.js      # session 모드 토큰 추출
│  │  │  ├─ plaud_download_audio.js     # 음성 다운로드 + Plaud Web 폴더 이동
│  │  │  ├─ whisper_transcribe.py       # faster-whisper 음성 인식
│  │  │  └─ health_check.sh             # 세션 헬스체크
│  │  └─ templates/
│  │     └─ daily_summary.md            # ADHD 친화 요약 템플릿
│  ├─ agents/plaud-collector.md         # 결과 검증·요약 서브에이전트
│  └─ commands/plaud-daily.md           # /plaud-daily 슬래시 커맨드
├─ input/                               # 임시 다운로드 (자동 비워짐)
└─ logs/                                # 실행 로그
```

런타임에 만들어지는 외부 디렉토리:

| 경로 | 용도 |
|---|---|
| `~/PLAUD-Data/` | 처리 완료 음성 원본 아카이브 |
| `~/.plaud-pipeline-profile/` | session 모드용 브라우저 프로필 (구글 쿠키) |
| `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Transcripts/` | 인식 결과 `YYYY-MM-DD.md` |
| `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Daily Summary/` | (선택) 요약 결과 |

## 자주 쓰는 명령

```bash
npm run check                # 전체 상태 점검
npm run pipeline             # 파이프라인 수동 실행
npm run health               # 세션 헬스체크
npm run first-login          # 구글 로그인 (브라우저)
npm run register-cron        # cron 등록
npm run register-cron:dry    # 등록 미리보기
npm run uncron               # cron 항목 제거
```

상세 운영 시나리오는 [`SCENARIOS.md`](SCENARIOS.md) 참고.

## Claude Code에서 사용하기

이 프로젝트는 Claude Code 내 자연어 발화로 동작한다:

```
"오늘 plaud 가져와줘"
"plaud-collector로 ~/PLAUD-Data 30일 이상 파일 후보 보고해"
"plaud 헬스체크 돌려"
/plaud-daily
/plaud-daily 2026-04-29
```

스킬·서브에이전트·슬래시 커맨드가 자동으로 트리거된다.

## 환경변수

[`SCENARIOS.md`의 부록 B](SCENARIOS.md#부록-b-환경변수-빠른-참조) 참고.

## 문제 해결

| 증상 | 원인 / 조치 |
|---|---|
| "토큰을 찾을 수 없습니다" | Plaud Web UI 변경. `plaud_login_and_download.js` 셀렉터 조정 |
| "PLAUD 세션 만료" 알림 | `npm run first-login` 다시 실행 |
| "PLAUD Vault 쓰기 불가" 알림 | Full Disk Access 권한 추가 (위 빠른 시작 참조) |
| "faster-whisper 설치 실패" | `brew install python@3.11` 후 `rm -rf .venv && ./setup.sh` |
| 첫 실행이 너무 느림 | Whisper 모델(1.5GB) 첫 다운로드. `~/.cache/huggingface/`에 캐시됨 |
| `input/failed/`에 파일이 쌓임 | 파일명이 `YYYY-MM-DD HH_MM_SS.mp3` 형식이 아닐 가능성 |

상세는 [`SCENARIOS.md`](SCENARIOS.md)의 시나리오 5~11.

## 보안 주의사항

- `.env`는 절대 커밋하지 말 것 (이미 `.gitignore`에 포함)
- `~/.plaud-pipeline-profile/`에는 구글 OAuth 쿠키가 들어 있다. 절대 공유/외부 백업 금지
- 자격증명을 로그에 출력하지 않도록 주의 (스크립트는 이미 토큰 prefix 12자만 표시)
- `crontab` 자동 등록 시 기존 crontab은 `logs/crontab.backup.YYYYMMDD-HHMM.txt`로 자동 백업됨

## 다른 사람에게 공유할 때

```
PLAUD 자동 녹음 시작 → 터미널 한 줄:
  npx create-plaud-pipeline my-recording

GitHub: https://github.com/gaebalai/plaud-auto-recording
npm:    https://www.npmjs.com/package/create-plaud-pipeline
```

## 유지보수 (개발자용)

### 일반 코드 수정 → GitHub만 push
CLI는 GitHub의 최신 `main` 브랜치를 그대로 가져오므로, 보통은 push만 해도 사용자가 다음 `npx` 실행에서 새 코드를 받는다.

```bash
git add . && git commit -m "..." && git push
```

### CLI 동작 자체가 바뀐 경우 → republish

```bash
cd cli
npm version patch    # 1.0.0 → 1.0.1
# npm version minor  # 1.0.0 → 1.1.0 (기능 추가)
# npm version major  # 1.0.0 → 2.0.0 (호환성 깨짐)
npm publish
```

### 새 릴리즈 태그

```bash
git tag -a v1.1.0 -m "1.1.0"
git push origin v1.1.0
gh release create v1.1.0 --title "1.1.0" --generate-notes
```

## 라이선스

MIT — [`LICENSE`](LICENSE) 참고.

## 감사

원본 아이디어/구성 출처: [`plaude.md`](plaude.md). 이 프로젝트는 그 가이드를 macOS + Claude Code 환경에 맞춰 재구성하고 운영 안정성 항목을 보강한 것이다.
