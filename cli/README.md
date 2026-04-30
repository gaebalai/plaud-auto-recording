# create-plaud-pipeline

Bootstrap a [PLAUD NotePin](https://www.plaud.ai/) auto-recording pipeline on macOS — Whisper transcription + Obsidian Vault output, fully automated.

## Quick start

```bash
npx create-plaud-pipeline my-recording
```

Or with `npm create`:
```bash
npm create plaud-pipeline my-recording
```

This will:
1. Clone the project template into `my-recording/`
2. Run `setup.sh` — install Node + Python dependencies, set up directories
3. Print the next steps

After bootstrap:
```bash
cd my-recording
# Edit .env (PLAUD_AUTH_MODE + credentials)
npm run first-login    # if using Google OAuth (session mode)
npm run pipeline       # test run
npm run register-cron  # daily automation
```

## Options

```
--auto         Run `setup.sh --yes` automatically (no confirmation prompt)
--no-setup     Clone only; run setup.sh manually later
--branch <b>   Use a non-default branch
-h, --help
```

## What you get

A self-contained project with:
- Playwright-based PLAUD Web automation (password or Google OAuth)
- Local faster-whisper transcription (`large-v3-turbo`, Korean)
- Obsidian Vault integration (`Transcripts/YYYY-MM-DD.md`)
- macOS notification on failures
- cron auto-registration with backups
- Session health checks
- Concurrent-execution lock
- Log rotation

See the project [README.md](https://github.com/gaebalai/plaud-auto-recording#readme) and [SCENARIOS.md](https://github.com/gaebalai/plaud-auto-recording/blob/main/SCENARIOS.md) for full details.

## Requirements

- macOS (Apple Silicon or Intel)
- Node.js 18+
- Python 3.10+ (3.11 recommended for faster-whisper compatibility)

## License

MIT
