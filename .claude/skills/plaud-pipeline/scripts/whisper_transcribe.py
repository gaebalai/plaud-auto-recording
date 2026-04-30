#!/usr/bin/env python3
"""PLAUD 음성 파일을 faster-whisper로 인식해 Obsidian Vault에 날짜별 Markdown으로 저장."""
import os
import shutil
from datetime import datetime, timedelta
from pathlib import Path

from faster_whisper import WhisperModel

HOME = Path.home()
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_DIR = SCRIPT_DIR.parent.parent.parent.parent

INPUT_DIR = Path(os.environ.get("PLAUD_INPUT_DIR", PROJECT_DIR / "input"))
PROCESSED_DIR = Path(os.environ.get("PLAUD_PROCESSED_DIR", HOME / "PLAUD-Data"))
OUTPUT_DIR = Path(os.environ.get(
    "PLAUD_OUTPUT_DIR",
    HOME / "Library/Mobile Documents/iCloud~md~obsidian/Documents/Transcripts",
))

MODEL_SIZE = os.environ.get("WHISPER_MODEL", "large-v3-turbo")
DEVICE = os.environ.get("WHISPER_DEVICE", "cpu")
COMPUTE_TYPE = os.environ.get("WHISPER_COMPUTE_TYPE", "int8")
BEAM_SIZE = int(os.environ.get("WHISPER_BEAM_SIZE", "5"))
LANGUAGE = "ko"
TASK = "transcribe"


def parse_start_dt(filename: str) -> datetime:
    base = os.path.splitext(filename)[0].strip()
    for fmt in ("%Y-%m-%d %H_%M_%S", "%Y-%m-%d_%H_%M_%S"):
        try:
            return datetime.strptime(base, fmt)
        except ValueError:
            continue
    raise ValueError(f"파일명 형식 오류 (지원: 'YYYY-MM-DD HH_MM_SS'): {filename}")


def transcribe_collect(model: WhisperModel, file_path: Path):
    file = file_path.name
    start_dt = parse_start_dt(file)
    date_key = start_dt.strftime("%Y-%m-%d")

    segments, _info = model.transcribe(
        str(file_path),
        task=TASK,
        language=LANGUAGE,
        vad_filter=True,
        vad_parameters=dict(
            min_silence_duration_ms=5000,
            speech_pad_ms=1000,
        ),
        beam_size=BEAM_SIZE,
        temperature=0.0,
        condition_on_previous_text=False,
    )

    rows = []
    for seg in segments:
        if not seg.text:
            continue
        abs_start = start_dt + timedelta(seconds=seg.start)
        line = f"[{abs_start.strftime('%H:%M:%S')}] {seg.text.strip()}"
        rows.append((abs_start, line))

    return date_key, rows


def unique_dest(directory: Path, name: str) -> Path:
    """직속 directory에 동일 이름이 있으면 -1, -2 ... suffix를 붙여 충돌 회피."""
    candidate = directory / name
    if not candidate.exists():
        return candidate
    stem = candidate.stem
    suffix = candidate.suffix
    counter = 1
    while True:
        candidate = directory / f"{stem}-{counter}{suffix}"
        if not candidate.exists():
            return candidate
        counter += 1


def main() -> int:
    print(f"CWD: {Path.cwd()}")
    print(f"INPUT_DIR: {INPUT_DIR}")
    print(f"PROCESSED_DIR: {PROCESSED_DIR}")
    print(f"OUTPUT_DIR: {OUTPUT_DIR}")

    INPUT_DIR.mkdir(parents=True, exist_ok=True)
    PROCESSED_DIR.mkdir(parents=True, exist_ok=True)
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    failed_dir = INPUT_DIR / "failed"
    failed_dir.mkdir(parents=True, exist_ok=True)

    targets = sorted(
        f for f in INPUT_DIR.iterdir()
        if f.is_file() and f.suffix.lower() in {".mp3", ".wav", ".m4a", ".flac"}
    )

    if not targets:
        print("처리 대상 없음: input 폴더가 비어 있습니다.")
        return 0

    print(f"모델 로딩 중: {MODEL_SIZE} (device={DEVICE}, compute={COMPUTE_TYPE})...")
    try:
        model = WhisperModel(MODEL_SIZE, device=DEVICE, compute_type=COMPUTE_TYPE)
    except Exception as e:
        print(f"모델 시작 오류: {e}")
        return 1

    print(f"처리 시작: {len(targets)}개 파일")

    fail = 0
    for i, src in enumerate(targets, 1):
        print(f"[{i}/{len(targets)}] 분석 중... {src.name}")

        try:
            date_key, rows = transcribe_collect(model, src)

            if not rows:
                print(f"  -> 음성 데이터 없음 (스킵): {src.name}")
            else:
                out_daily = OUTPUT_DIR / f"{date_key}.md"
                with out_daily.open("a", encoding="utf-8") as w:
                    for _, line in rows:
                        w.write(line + "\n")
                print(f"  -> 출력 완료: {out_daily} ({len(rows)} 라인 추가)")

            dst = unique_dest(PROCESSED_DIR, src.name)
            shutil.move(str(src), str(dst))
            print(f"  -> 이동 완료: {dst}")

        except Exception as e:
            print(f"오류 발생 ({src.name}): {e}")
            fail += 1
            try:
                failed_dst = unique_dest(failed_dir, src.name)
                shutil.move(str(src), str(failed_dst))
                print(f"  -> failed/로 격리: {failed_dst}")
            except Exception as move_err:
                print(f"  -> failed/ 격리 실패 (input에 남음): {move_err}")
            continue

    print(f"모든 처리가 완료되었습니다. 실패: {fail}")
    return 0 if fail == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
