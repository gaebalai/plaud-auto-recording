---
description: PLAUD 일일 파이프라인 실행 (다운로드 → Whisper 인식 → Vault 저장 → 요약). 인수로 날짜를 주면 해당일 요약, 없으면 오늘 처리.
argument-hint: "[YYYY-MM-DD]"
---

PLAUD 일일 자동 수집 파이프라인을 실행한다.

## 절차

1. **사전 점검**: `${CLAUDE_PROJECT_DIR}/.env`가 없으면 즉시 사용자에게 `cp .env.example .env` 후 자격증명 입력하라고 안내하고 중단

2. **파이프라인 실행**: Bash 도구로 아래를 실행:
   ```bash
   bash ${CLAUDE_PROJECT_DIR}/.claude/skills/plaud-pipeline/scripts/run_pipeline.sh
   ```
   종료 코드와 마지막 로그 파일(`${CLAUDE_PROJECT_DIR}/logs/plaud_*.log` 중 가장 최신)을 확인

3. **대상 날짜 결정**: `$ARGUMENTS`가 비어 있으면 오늘 날짜(YYYY-MM-DD), 주어졌다면 그 값 사용

4. **Transcripts 존재 확인**: `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Transcripts/{날짜}.md` 존재 여부 점검

5. **요약 위임 (Task tool 호출)**: Transcripts 파일이 존재하면 **Task tool**을 다음 인수로 호출해 ADHD 친화 요약을 위임한다:
   - `subagent_type`: `"plaud-collector"`
   - `description`: `"PLAUD {날짜} 요약 작성"` (3~5단어)
   - `prompt`: 다음 항목을 자연어로 전달
     - 대상 날짜
     - Transcripts 파일 절대 경로
     - 요약 저장 경로: `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Daily Summary/{날짜}_summary.md`
     - 같은 이름 파일이 이미 있으면 덮어쓰지 말고 사용자에게 확인하라는 지시
     - 템플릿 경로: `${CLAUDE_PROJECT_DIR}/.claude/skills/plaud-pipeline/templates/daily_summary.md`

6. **사용자 보고**: 다음을 1~2문단으로 정리해 출력
   - 처리된 음성 파일 수와 인식 라인 수 (run_pipeline.sh 로그에서 추출)
   - Whisper 처리 시간 (로그의 `Whisper 처리 시간:` 라인)
   - Transcripts 파일 경로
   - 요약 저장 경로 (생성된 경우)
   - `partial=1`로 끝났으면 부분 실패 사실과 `logs/plaud_*.log` 경로
   - 발생한 오류와 권장 조치 (있다면)

## 주의

- 자격증명(`PLAUD_PASSWORD`, 토큰)은 어떤 출력에도 포함하지 않는다
- 같은 이름 요약 파일이 이미 있으면 plaud-collector가 덮어쓰지 않도록 prompt에 명시
- `run_pipeline.sh` 종료 코드가 0이 아니어도 부분 실패(partial=1)인 경우는 다음 단계 진행 가능. 완전 실패면 거기서 보고 후 중단
