# 운영 시나리오

이 문서는 일상 운영 중 마주칠 수 있는 상황을 시간순으로 따라가며 정리한다. 각 시나리오는 "무엇을 할지 → 어떤 명령을 실행할지 → 무엇을 확인할지"의 세 부분으로 구성된다.

---

## 시나리오 1. 처음 설치 (한 번)

PLAUD를 막 받아서 자동화하고 싶은 시점.

### 무엇을 할지
1. 부트스트랩 (npx 한 줄)
2. 자격증명 입력 (`.env`)
3. 구글 로그인 1회 (session 모드일 때)
4. cron 등록 (선택)
5. macOS Full Disk Access 권한 부여 (필수)

### 가장 간단한 길 — npx 한 줄

```bash
npx create-plaud-pipeline my-recording
```

이 한 줄이 자동으로:
- GitHub에서 최신 코드 복제
- Node + Python 의존성 설치
- `~/PLAUD-Data/`, Vault 폴더 등 디렉토리 준비
- `.env` 자동 생성

### 그 다음 단계

```bash
cd my-recording

# .env 편집: PLAUD_AUTH_MODE=session 또는 password 선택
# vi .env  또는  code .env

npm run first-login                           # session 모드일 때만, 브라우저에서 직접 구글 로그인
npm run pipeline                              # 시험 실행 (수동, 1회)
npm run register-cron                         # cron 두 줄 자동 등록
```

### 다른 설치 방법

```bash
# B) curl | bash 한 줄
curl -fsSL https://raw.githubusercontent.com/gaebalai/plaud-auto-recording/main/bootstrap.sh \
  | bash -s -- my-recording

# C) git clone + setup
git clone https://github.com/gaebalai/plaud-auto-recording.git my-recording
cd my-recording && ./setup.sh
```

### 시스템 권한 (한 번만, 시스템 설정에서)
1. **시스템 설정 → 개인정보 보호 및 보안 → 전체 디스크 접근 권한**
2. `+` → `⌘⇧G` → `/usr/sbin/cron` 입력 → 추가
3. 토글 켜기

### 확인
```bash
npm run check    # 의존성/폴더/Vault/cron 등록 상태 한눈에
```

---

## 시나리오 2. 매일 자동 운영 (cron 등록 후)

설치가 끝나면 사용자가 할 일은 사실상 없다.

### 자동으로 일어나는 일
- **매일 03:00** — `run_pipeline.sh` 자동 실행
  - Plaud Web에 (헤드리스) 접속
  - 새 녹음 다운로드 → `~/PLAUD-Data/`로 이동
  - faster-whisper 음성 인식
  - Obsidian Vault `Transcripts/YYYY-MM-DD.md`에 추가 기입
- **매주 월 09:00** — `health_check.sh`로 세션 살아있는지 확인 (session 모드)

### 사용자가 알아채는 시점
정상 운영 중에는 알림이 뜨지 않는다(노이즈 방지). 알림이 뜨면 어떤 종류인지 확인:

| 알림 제목 | 의미 | 조치 |
|---|---|---|
| PLAUD 파이프라인 부분 실패 | 일부 파일만 실패 | `logs/plaud_*.log` 확인, 보통 다음 실행에 자동 복구 |
| PLAUD 파이프라인 실패 | 전체 실패 | `logs/plaud_*.log` 확인 |
| PLAUD 세션 만료 임박 | 구글 세션 만료 | 시나리오 5 참조 |
| PLAUD Vault 쓰기 불가 | Full Disk Access 권한 누락 | 시나리오 8 참조 |
| PLAUD 자격증명 누락 | `.env` 비어있음 | `.env` 확인 |
| PLAUD 파이프라인 스킵 | 이미 실행 중 (수동+cron 충돌 등) | 무시해도 됨 |

---

## 시나리오 3. 수동으로 즉시 한 번 돌리기

녹음한 직후, "지금 바로 처리하고 싶다"는 경우.

### 명령
```bash
npm run pipeline
```

또는 Claude Code 안에서:
```
"지금 PLAUD 가져와줘"
"오늘 녹음 처리해"
```

또는 슬래시 커맨드:
```
/plaud-daily
```

### 동시 실행 방지
cron이 03:00에 돌고 있는 동안 수동으로 또 실행해도 안전. lock 파일이 두 번째 실행을 자동으로 건너뛴다 ("이미 실행 중" 알림).

---

## 시나리오 4. 그날치 ADHD 친화 요약 만들기

Transcripts에 원문이 쌓여 있고, "오늘 뭐 했지?"를 5초 안에 보고 싶은 경우.

### Claude Code에서
```
/plaud-daily
```
인수 없이 실행 → 오늘 날짜 처리. 슬래시 커맨드가 다음을 순서대로 수행:
1. `run_pipeline.sh` 호출 (혹시 안 받은 녹음 있으면 받기)
2. 오늘 날짜의 `Transcripts/2026-04-30.md` 확인
3. **plaud-collector 서브에이전트에 위임** → ADHD 친화 요약 작성
4. `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Daily Summary/2026-04-30_summary.md` 저장

### 다른 날짜 요약
```
/plaud-daily 2026-04-29
```

### 출력 형태 (요약)
```markdown
## 📌 핵심 요점 5가지
- **9:30 회의에서 신규 프로젝트 킥오프**
- ...

## 🕒 시간순 타임라인
☀️ 오전 (6시~12시)
- 9:00 회의실 A — 프로젝트 X 일정 논의
...

## 📋 할 일 & 리마인더
- [ ] 김 매니저에게 이메일
- [ ] 카페 결제 영수증 정산
...
```

---

## 시나리오 5. 세션 만료 알림이 떴을 때 (구글 로그인 모드)

월요일 오전 헬스체크에서 "PLAUD 세션 만료 임박" 알림.

### 무엇이 일어났는가
구글 OAuth 세션 쿠키가 만료됐다(보통 수 주마다). 자동 갱신 불가능 — 사용자가 직접 1회 로그인해야 한다.

### 조치 (5분)
```bash
npm run first-login
```
브라우저가 떠서 평소처럼 구글 로그인 → 세션 갱신 → 자동 종료. 다음 cron부터 정상 동작.

### 확인
```bash
npm run health    # ✓ 세션 정상 떠야 함
```

---

## 시나리오 6. 특정 파일이 인식 실패한 경우

Whisper가 어떤 파일을 처리하다 오류 → 자동으로 `input/failed/`로 격리.

### 격리된 파일 확인
```bash
ls -la input/failed/
```

### 다음 실행 영향
없음. 격리된 파일은 다음 cron에서 자동 스킵되어 무한 재시도 루프에 빠지지 않는다.

### 다시 시도
원인을 알고 고친 후:
```bash
mv input/failed/2026-04-29\ 14_30_22.mp3 input/
npm run pipeline
```

### 흔한 원인
- 파일명이 `YYYY-MM-DD HH_MM_SS.mp3` 형식이 아님 → 파일명 수동 수정
- 파일이 손상/0바이트 → 손실. Plaud Web에서 다시 받기
- 디스크 가득 참 → 시나리오 7 참조

---

## 시나리오 7. 음성 보관소 정리

`~/PLAUD-Data/`가 너무 커졌을 때(보통 6개월~1년에 100GB 정도).

### 현재 용량 확인
```bash
du -sh ~/PLAUD-Data/
ls -la ~/PLAUD-Data/ | head
```

### 30일 이상 된 파일 후보 보기 (삭제 X, 목록만)
```bash
find ~/PLAUD-Data/ -type f -mtime +30 -name "*.mp3" | head -20
```

### Claude Code에 위임
```
"plaud-collector로 ~/PLAUD-Data 30일 이상 파일 후보 보고해줘"
```

서브에이전트가 목록만 보여준다. 자동 삭제는 하지 않음.

### 직접 삭제
인식 결과 `.md`가 있으면 원본은 사실 없어도 됩니다. 신중하게:
```bash
# 먼저 dry-run
find ~/PLAUD-Data/ -type f -mtime +90 -name "*.mp3" -print

# 진짜 삭제 (90일 이상)
find ~/PLAUD-Data/ -type f -mtime +90 -name "*.mp3" -delete
```

---

## 시나리오 8. Vault 쓰기 권한 누락 (Full Disk Access)

알림: "PLAUD Vault 쓰기 불가 — 전체 디스크 접근 권한이 없을 수 있음"

### 원인
cron에서 띄운 프로세스가 iCloud Drive 폴더에 쓰지 못함. macOS 보안 정책상 명시적 권한 필요.

### 조치
1. 시스템 설정 → 개인정보 보호 및 보안 → 전체 디스크 접근 권한
2. `+` → `⌘⇧G` → `/usr/sbin/cron` 추가 후 토글
3. (보강) 같은 절차로 `/bin/bash`도 추가

### 확인
```bash
npm run pipeline    # 알림 안 뜨면 OK
npm run check       # "쓰기 권한 OK" 확인
```

---

## 시나리오 9. 자동화 일시 중단 / 재개

여행/병가/녹음 안 하는 기간.

### 일시 중단
```bash
npm run uncron        # cron 두 줄만 제거 (다른 cron 보존, 백업 자동)
```

### 재개
```bash
npm run register-cron
```

### `.env`만 그대로 두고 코드 보존
프로젝트 폴더는 그대로 두고 cron만 빠졌다 들어오는 식이라 깔끔.

---

## 시나리오 10. 새 맥으로 이전

기기 교체 시. 이제 npx 한 줄이라 옮길 게 거의 없다.

### 무엇을 옮길지
1. **코드 — 옮길 필요 없음**. `npx create-plaud-pipeline`으로 새로 받음
2. **`.env`** — 자격증명만 따로 백업 (안전한 곳에)
3. **`~/PLAUD-Data/`** — 음성 원본 보존하고 싶으면 (외장 SSD나 클라우드로 백업)
4. **`~/.plaud-pipeline-profile/`** — 구글 로그인 세션. **옮기지 말고 새 맥에서 새로 로그인 권장** (보안)

### 새 맥에서

```bash
# 1) 새 부트스트랩
npx create-plaud-pipeline plaud-recording
cd plaud-recording

# 2) 자격증명 복원
# 백업한 .env 내용을 새 .env에 붙여넣기 (또는 cp)

# 3) 구글 로그인 새로 (session 모드일 때)
npm run first-login

# 4) cron + Full Disk Access (시나리오 1과 동일)
npm run register-cron
# 시스템 설정 > 개인정보 보호 및 보안 > 전체 디스크 접근 > /usr/sbin/cron 추가

# 5) 점검
npm run check
```

### Obsidian Vault는 어떻게?
이미 iCloud 동기화라 **별도 이전 작업 없음**. 새 맥에서 Obsidian 깔고 같은 iCloud 계정 로그인하면 자동 동기화.

### Obsidian Vault는?
이미 iCloud 동기화라 **별도로 옮길 필요 없음**. 새 맥에서 Obsidian 깔고 같은 iCloud 계정 로그인하면 자동 동기화.

---

## 시나리오 11. Plaud Web UI/API가 바뀌었을 때

가끔 발생. 보통 다운로드 단계에서 실패한다.

### 증상
- "토큰을 찾을 수 없습니다"
- "이메일 입력란을 찾지 못했습니다"
- "목록 취득 실패: 404 / 401"

### 진단
```bash
npm run pipeline 2>&1 | tee /tmp/debug.log
```
또는 Claude Code에:
```
"plaud-collector로 가장 최근 logs/plaud_*.log 분석해줘"
```

### 일반적인 수정 위치
- **로그인 셀렉터** — `.claude/skills/plaud-pipeline/scripts/plaud_login_and_download.js`의 `emailSelectors`/`passwordSelectors`
- **API base URL** — `.env`의 `PLAUD_API_BASE`를 `https://api.plaud.ai`로 시도
- **토큰 키 이름** — `plaud_session_login.js`의 `TOKEN_KEYS` 배열에 후보 추가

---

## 시나리오 12. 처음 받은 녹음의 양이 너무 많을 때

PLAUD를 며칠 동안 안 받아둔 채 처음 자동화를 도입한 경우. 한 번에 수십 개 파일이 들어옴.

### 예상 처리 시간
- 5시간 음성 한 파일 ≈ Whisper CPU 30분 ~ 1시간
- 10개 파일 ≈ 5~10시간

### 안전한 첫 실행
```bash
# 다운로드 한도 제한해서 5개씩 끊어 처리
PLAUD_DOWNLOAD_LIMIT=5 npm run pipeline    # (현재 미구현, 필요 시 추가)
```

또는 그냥 시동 걸어두고 잠들기:
```bash
nohup bash .claude/skills/plaud-pipeline/scripts/run_pipeline.sh > /tmp/first.log 2>&1 &
```

다음날 아침 `tail /tmp/first.log` 또는 `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Transcripts/`에 파일들 들어왔는지 확인.

---

## 부록 A. 자주 쓰는 명령 한눈에

```bash
npm run check                # 전체 상태 점검 (변경 없음)
npm run pipeline             # 파이프라인 1회 수동 실행
npm run health               # 세션 헬스체크 (구글 모드)
npm run first-login          # 구글 로그인 (브라우저 뜸)
npm run register-cron        # cron 자동 등록
npm run register-cron:dry    # 등록 미리보기
npm run register-cron:check  # 등록 상태 확인
npm run uncron               # cron 항목 제거
```

## 부록 B. 환경변수 빠른 참조

| 변수 | 의미 | 기본값 |
|---|---|---|
| `PLAUD_AUTH_MODE` | `password` 또는 `session` | `password` |
| `PLAUD_EMAIL`, `PLAUD_PASSWORD` | password 모드 자격증명 | (필수) |
| `PLAUD_PROFILE_DIR` | session 모드 프로필 위치 | `~/.plaud-pipeline-profile` |
| `PLAUD_MOVE_TO_FOLDER_ID` | 다운로드 후 옮길 Plaud Web 폴더 | (선택) |
| `PLAUD_API_BASE` | API 엔드포인트 | `https://api-apne1.plaud.ai` |
| `PLAUD_OUTPUT_DIR` | Vault Transcripts 경로 override | iCloud Obsidian 기본 경로 |
| `PLAUD_PROCESSED_DIR` | 처리 완료 음성 폴더 | `~/PLAUD-Data` |
| `PLAUD_NOTIFY_ON_SUCCESS` | 성공도 알림? | `0` (실패만) |
| `PLAUD_LOG_RETENTION_DAYS` | 로그 보관 일수 | `30` |
| `PLAUD_LOG_TRUNCATE_BYTES` | 단일 누적 로그 truncate 기준 | `5242880` (5MB) |
| `WHISPER_MODEL` | Whisper 모델 | `large-v3-turbo` |
| `WHISPER_DEVICE` | `cpu` (macOS는 mps 미지원) | `cpu` |
| `WHISPER_COMPUTE_TYPE` | `int8`(CPU 권장) / `float16` | `int8` |
