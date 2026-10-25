# Working with Claude on this project

What Claude needs before coding starts, and how to keep the work fast. Written 2026-10-24.

## Already in place

- Read access to `KRakenoZavr/recognize-everything-vr` on GitHub.
- Rust stable 1.97 with `cargo`, `clippy` and `rustfmt` in the cloud container.
- Network from the cloud container to crates.io, static.rust-lang.org, the Gemini API host
  and the Anthropic API host.
- An approved local folder on your PC: `C:\AI\projects\recognize-everything-vr`.
- `CLAUDE.md` and `docs/` in this repo, plus shared project memory.

## What Claude needs from you

### 0. GitHub write access (needed now)

Claude can read the repository but pushes and branch creation are refused (HTTP 403,
"Resource not accessible by integration"). To fix it, reconnect GitHub at
https://claude.ai/connect-github and make sure the Claude GitHub App is installed on this
repository with write access (https://github.com/apps/claude/installations/select_target).
Until then Claude writes files into your local folder and you commit them.

### 1. A cloud environment for the project (needed for phase 1)

The project currently runs on the built-in cloud environment, which has no settings. Create
one in **Project settings > Cloud environment > Add cloud environment**, then set:

| Setting | Value | Needed for |
| --- | --- | --- |
| Environment variable `GEMINI_API_KEY` | A Google AI Studio API key, ideally with a spending limit | Phase 1, the default `Describer` |
| Environment variable `ANTHROPIC_API_KEY` | Optional | Phase 2 comparison harness |
| Environment variable `OPENAI_API_KEY` | Optional | Phase 2 comparison harness |
| Allowed domain `api.openai.com` | Currently blocked | Only if you add the OpenAI key |
| Allowed domain `dl.google.com` | Currently blocked | Downloading the Android NDK to build Quest APKs in the cloud |
| Keep "Allow package managers" ticked | | crates.io and rustup |

Never paste keys into chat or commit them. Claude reads them from the environment.

### 2. Your PC and headset for Quest work (needed for phase 3)

Cloud sessions cannot reach a headset. Quest builds get installed and tested on your PC
through a Remote Control session in the approved folder. On the PC:

- Quest 3 or 3S on Horizon OS v74 or later, in developer mode (Meta developer account and
  the Meta Horizon phone app)
- Android platform-tools (`adb`), with the headset connected by USB or wireless adb
- Rust via `rustup`, plus `rustup target add aarch64-linux-android`
- Android NDK and `cargo install cargo-ndk`
- The Claude desktop app or `claude remote-control` running in the project folder

Claude can install most of the PC tooling through Remote Control once you approve it.

### 3. Test data (needed for phase 2)

- 50 to 100 photos of real objects you would point at, each with the name you expect.
  Upload them to the project files or drop them in `tests/fixtures/`.
- Later, a few short recordings from the Quest camera so most work can run on the desktop.

### 4. Open decisions

- Monthly budget per user (open).
- License file. AGPL-3.0 fits if YOLO26 is bundled.

## How to get the most out of Claude

1. **One thread per goal.** For example "Build the Gemini adapter" or "Quest OpenXR shell".
   Say what "done" looks like (an exit criterion from `docs/roadmap.md` works well).
2. **Keep decisions written down.** Claude reads `CLAUDE.md` and `docs/decisions.md` at the
   start of every session. Tell Claude when something changes and it updates them in the
   same PR.
3. **Real keys over mocks.** With API keys in the environment Claude runs real calls and
   measures real latency instead of guessing.
4. **CI first.** Phase 0 adds GitHub Actions for fmt, clippy and tests, so every PR checks
   itself and Claude fixes failures without you.
5. **Desktop first, headset second.** Everything except the Quest client runs on the
   desktop with webcam input or recorded frames. Batch headset tests into a few Remote
   Control sessions instead of many small ones.
6. **Small PRs, quick reviews.** Claude opens a PR per goal and watches it; you review and
   merge. Claude never merges or pushes to `main`.
7. **Big files outside git.** Model weights and recordings go in project files or Git LFS,
   not in normal commits.
8. **Fewer prompts in local sessions.** `.claude/settings.json` allows common `cargo`
   commands so local Claude Code sessions ask less often.
