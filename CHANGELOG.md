# Changelog

## 1.0.5 — 2026-10-26

- Fix the launcher passing `-Action` as a positional value (array splatting) by switching `Invoke-Sync` to hashtable splatting. The previous launcher could fail with "The argument '-Action' does not belong to the set...".
- Add an end-to-end launcher test using a compiled fake DSH executable.

## 1.0.4 — 2026-10-26

- Fix the installer's final message to point at the **DeepSeek Harness** synced entry instead of the removed `DSH - DshKit` name.

## 1.0.3 — 2026-10-25

- Remove a test fixture that contained a fragment of a local Windows user name.
- Publish with a GitHub noreply commit identity; no personal email in commit metadata.
- Re-created repository history with a single sanitized commit.

## 1.0.2 — 2026-10-25

- Make the familiar **DeepSeek Harness** Start Menu entry the synced launcher; the bypass entry is now **DeepSeek Harness (原生启动)**.
- Move the old `DSH - DshKit` and `(直接启动)` shortcuts to the local backup folder.
- Update README and installer output for the new entry names.

## 1.0.1 — 2026-10-25

- Use robocopy for session copies when DSH is not running (fixes 8.3 short-path handling on CI/other machines).
- Preserve a zero exit code after successful robocopy runs, so `Push-DshKit.cmd` is not reported as failed.
- Add deterministic tests for both session-copy paths and CI exit status.

## 1.0.0 — 2026-10-25

- First public release.
- Pull before DSH launch, Push after DSH exits.
- Refuse Push while DSH is running (no silent partial sync).
- Skip session/projection files newer than the local copy, preventing stale machines from overwriting newer state.
- Lock file with heartbeat and 10-minute automatic takeover.
- UTF-8 BOM + CRLF for PowerShell scripts; ASCII + CRLF for batch files.
- Installer writes `config.json`, creates `~/.dsh/skills` junction and Start Menu shortcuts.
- Optional `-InitialPush` / `-InitialPull` for first-time setup.
- Tests and GitHub Actions workflow.
