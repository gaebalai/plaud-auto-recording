# PLAUD 자동 녹음 — 처음부터 끝까지 7단계 가이드

비개발자도 따라할 수 있게 처음부터 끝까지 정리. 전체 소요 시간 약 30분 (의존성 설치 5~10분 포함).

이후로는 손 댈 일 거의 없습니다 — 진짜로 자동.

---

## 0. 사전 준비 (한 번만, 5분)

### Homebrew (없으면)
**터미널** 앱(Spotlight `⌘+Space` → "터미널")을 열고:
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### Node.js
```bash
brew install node
```

확인:
```bash
node --version    # v18 이상이면 OK (예: v25.8.0)
```

이미 깔려있으면 건너뛰셔도 됩니다.

---

## 1. 토큰 미리 받아두기 (선택, 시간 절약)

설치 중에도 받을 수 있지만, 미리 받아두면 의존성 설치 시간(5~10분)을 활용할 수 있습니다.

> Plaud에 비밀번호가 설정되어 있으면 이 단계 건너뛰셔도 됩니다.

### 토큰 받는 절차

1. **Chrome** 또는 **Brave**(자동화 아닌 본인 브라우저)에서 https://web.plaud.ai 접속
2. 평소처럼 **구글 로그인** (자동화 아니므로 차단 없음)
3. 메인 화면(녹음 목록) 도달한 상태에서 **`⌘ + Option + I`** (개발자 도구)

#### 방법 A — Network 탭 ⭐ 가장 확실
4. 상단 탭에서 **Network** 선택
5. 페이지 **새로고침** (`⌘+R`)
6. 목록에서 `simple/web`, `filetag` 같은 요청 클릭
7. 우측 **Headers → Request Headers** 펼치기
8. **`authorization: Bearer eyJ...`** 라인의 **`eyJ...` 부분만 복사** (Bearer는 빼도 OK)

#### 방법 B — Local Storage (간단하지만 캐시될 수 있음)
4. 상단 탭에서 **Application** 선택
5. 좌측 트리: **Storage → Local Storage → `https://web.plaud.ai`**
6. 키 목록에서 **`tokenstr`** (또는 `token`, `access_token`) 클릭
7. 우측 Value 영역의 긴 문자열 (`eyJhbGc...`로 시작, 200~400자) **전체 복사**

> ⚠ **방법 B에서 401이 떨어지면 방법 A로** — Local Storage가 옛 토큰을 캐시하는 케이스가 있습니다.
>
> 💡 토큰을 미리 메모장 같은 곳에 붙여두면 다음 단계에서 곧장 사용 가능

---

## 2. 한 줄로 설치 (10분)

터미널에서:
```bash
npx create-plaud-pipeline my-recording
```

`my-recording`은 원하는 이름으로 바꿔도 됩니다 (예: `plaud`, `recordings`, `daily-log`).

처음 실행 시 npm이 "Ok to proceed?" 묻을 수 있습니다 → `y` 입력 → Enter.

### 무엇이 보이는가

순서대로 다음 화면이 나타납니다:

```
======================================================
  PLAUD 자동 녹음 파이프라인 설치
======================================================

  설치 도중 Plaud 인증 정보를 묻습니다.
  의존성 설치(5~10분) 동안 미리 토큰을 받아두면 빠릅니다:
  ...
======================================================

== 1. 시스템 점검 ==
✓ macOS
✓ Node.js v25.8.0
✓ Python 3.14.3
✓ Homebrew 사용 가능
✓ Obsidian Vault 발견: ...

== 다음 작업을 수행합니다 ==
  1) 프로젝트 로컬에 npm install playwright (~ 200MB)
  2) Playwright Chromium 다운로드 (~ 200MB)
  ...
계속하시겠습니까? [y/N]
```

→ **`y`** 입력 → Enter

```
== 2. Node.js 의존성 ==
▸ Node 의존성 설치 중...
✓ 의존성 설치 완료
▸ Chromium 브라우저 확인/다운로드 중...
✓ Chromium 준비 완료

== 3. Python 의존성 ==
⚠ Python 3.14.3는 faster-whisper 호환성이 불안정합니다.
Homebrew로 python@3.11을 자동 설치할까요? (5~10분 소요) [y/N]
```

→ **`y`** 입력 → Enter (Python 3.11이 자동 설치됩니다)

```
✓ python@3.11 설치 완료
✓ python@3.11 사용: /opt/homebrew/opt/python@3.11/bin/python3.11
✓ .venv 생성 (Python 3.11.x)
▸ Python 의존성 설치 중...
✓ Python 의존성 설치 완료

== 4. 디렉토리 준비 ==
✓ input/, logs/
✓ ~/PLAUD-Data
✓ Vault: Transcripts/, Daily Summary/

== 5. Plaud 인증 정보 (.env) ==

Plaud 계정 인증 방식:
  1) 비밀번호 (Plaud Web에서 비밀번호 설정 가능한 경우)
  2) 토큰 직접 입력 (구글 OAuth 단독 / 자동화 차단된 경우) ⭐ 권장
  3) 구글 OAuth 자동 로그인 (자주 차단됨)
  s) 일단 템플릿만, 나중에 직접 편집

선택 [1/2/3/s, 기본=2]:
```

→ **`2`** 입력 → Enter (토큰 모드)

```
== 토큰 받아오기 (5분) ==
  1) 본인 Chrome 또는 Brave에서 https://web.plaud.ai 접속
  ...

토큰을 붙여넣으세요 (빈 값 = 나중에 직접 편집):
```

→ 1단계에서 복사한 토큰 **`⌘+V`** → Enter

```
· 토큰 검증 중... (Plaud API 호출)
✓ 토큰 인증 성공 (API: https://api.plaud.ai)
✓ .env 작성 완료 (token 모드, chmod 600)

== 6. 실행 권한 ==
✓ 실행 권한 부여

== ✨ 설치 완료 ==

다음 단계:
  cd my-recording
  npm run pipeline       # 시험 실행
  npm run register-cron  # cron 자동 등록
```

---

## 3. 시험 실행 (1분)

```bash
cd my-recording
npm run pipeline
```

새 녹음이 없으면 즉시 끝납니다 (정상):
```
"미분류"에서 0개 파일 발견.
완료: 성공 0 / 실패 0
처리 대상 없음: input 폴더가 비어 있습니다.
===== 종료: 2026-04-30_2007 (partial=0) =====
```

이게 보이면 **인증/네트워크/Whisper 모두 정상**.

---

## 4. 실제 PLAUD 녹음으로 본격 시험 (10분)

1. **PLAUD NotePin**으로 1~2분 녹음 (NotePin 길게 누르기)
2. 휴대폰 **PLAUD 앱**이 NotePin에서 자동 동기화
3. **Wi-Fi 환경**에서 PLAUD 앱이 Plaud Web으로 자동 업로드
4. https://web.plaud.ai 에서 "미분류" 폴더에 새 파일 보이는지 확인 (보통 1~5분 안)
5. 다시 실행:
```bash
npm run pipeline
```

이번엔:
```
"미분류"에서 1개 파일 발견.
다운로드 중: 2026-04-30 21_30_00.mp3
완료: 성공 1 / 실패 0
--- 2단계: faster-whisper 음성 인식 ---
[1/1] 분석 중... 2026-04-30 21_30_00.mp3
  -> 출력 완료: ...Transcripts/2026-04-30.md (15 라인 추가)
  -> 이동 완료: ~/PLAUD-Data/...
Whisper 처리 시간: 35초
```

Obsidian에서 `Transcripts/2026-04-30.md` 확인 → 시간순 발화 텍스트가 들어와 있으면 ✅

---

## 5. 자동화 등록 (1분)

```bash
npm run register-cron
```

```
== PLAUD 항목을 등록/갱신합니다 ==
----- 변경 후 crontab 미리보기 -----
# plaud-auto-recording (pipeline)
0 3 * * * /bin/bash .../run_pipeline.sh >> .../logs/cron.log 2>&1
# plaud-auto-recording (health)
0 9 * * 1 /bin/bash .../health_check.sh >> .../logs/health.log 2>&1
------------------------------------
이 내용으로 crontab을 갱신하시겠습니까? [y/N]
```

→ **`y`** Enter

이제 매일 03:00에 자동 실행됩니다.

---

## 6. 시스템 권한 (한 번만, 2분)

cron이 iCloud Drive(Vault)에 쓰려면 필요합니다.

1. **시스템 설정** → **개인정보 보호 및 보안** → **전체 디스크 접근 권한**
2. 하단의 **`+`** 버튼 클릭
3. 파일 선택 창이 뜨면 **`⌘ + Shift + G`** 동시 누르기
   - 한글 입력기 켜져 있으면 단축키 안 먹힘 → **영문(ABC)으로 전환** 후 시도
4. 입력란에 **`/usr/sbin/cron`** 입력 → Enter
5. cron 파일 자동 선택됨 → **"열기"** 클릭
6. 목록의 cron **토글 ON**

> 💡 같은 절차로 **`/bin/bash`** 도 추가해두면 더 안정적

`⌘⇧G`가 안 먹힐 때 대안: Finder에서 `⌘⇧G` → `/usr/sbin` → cron 파일을 시스템 설정 창에 드래그.

---

## 7. 일상 운영 — 그 다음부턴 자동

이제 사용자가 따로 할 일 없습니다:

| 시점 | 자동으로 일어나는 일 |
|---|---|
| 매일 PLAUD 녹음 | NotePin → 휴대폰 앱 → Plaud Web 자동 동기화 |
| 매일 03:00 | cron이 다운로드 + Whisper + Vault 저장 |
| 매주 월 09:00 | 토큰 만료 사전 점검 |
| 토큰 만료 시 (수 주~수 개월) | "PLAUD 토큰 만료 임박" 알림 → 토큰 다시 복사 |
| 다른 알림 (실패 등) | 알림센터에 표시 |

### 그날치 ADHD 친화 요약 (선택)

Claude Code에서:
```
/plaud-daily
```
오늘의 발화 로그를 읽어 시간순 타임라인 + 핵심 5가지 + 할 일 목록으로 요약해 `Daily Summary/` 폴더에 저장.

### 자주 쓰는 명령

```bash
cd my-recording
npm run check                # 전체 상태 한눈에
npm run pipeline             # 수동 실행
npm run health               # 토큰 살아있는지
npm run register-cron:check  # cron 등록 상태
```

---

## 막힐 때

| 증상 | 해결 |
|---|---|
| `command not found: brew` | https://brew.sh — Homebrew 설치 |
| `command not found: node` | `brew install node` |
| 구글 로그인 차단 ("로그인할 수 없음") | 1단계 토큰 모드 사용 |
| `토큰 검증 실패` | 토큰을 다시 복사 (Local Storage의 다른 키 시도) |
| `PLAUD Vault 쓰기 불가` 알림 | 6단계 시스템 권한 다시 확인 |
| 녹음이 "미분류"에 없음 | Plaud Web에서 직접 어디 있는지 확인. 다른 폴더에 있으면 미분류로 이동 |

자세한 시나리오: [`SCENARIOS.md`](SCENARIOS.md) 참고.

---

## 시간 합산

| 단계 | 시간 |
|---|---|
| 0. 사전 준비 (Node 등) | 5분 (이미 있으면 0) |
| 1. 토큰 받기 | 2분 |
| 2. npx 설치 + 의존성 + Python 3.11 | 10~15분 (대부분 자동) |
| 3. 시험 | 1분 |
| 4. 실제 녹음 시험 | 5~10분 (녹음 동기화 시간 포함) |
| 5. cron 등록 | 1분 |
| 6. 시스템 권한 | 2분 |
| **합계** | **약 30분** |
