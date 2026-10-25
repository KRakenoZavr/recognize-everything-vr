# CLAUDE.md

Guidance for Claude (and humans) working in this repository. Read this first, then
`docs/decisions.md` for anything that was already decided.

## What we are building

Recognize Everything VR: the user points at any real object (with a hand or with their
gaze), the app highlights it, and on request shows a context menu with a deeper
description of the object.

- **First client:** Meta Quest 3 / 3S.
- **Must stay client-agnostic:** phones, tablets, webcams, any device with a camera.
  Nothing outside a client crate may depend on Quest, OpenXR or Android APIs.
- **AI models are swappable:** every model sits behind a Rust trait and is chosen by
  config. A better model later means a new adapter crate, not a rewrite.

## Current phase

**Phase 0: skeleton.** Architecture, tools, languages and roadmap only. No feature code
yet. See `docs/roadmap.md` for the phases and their exit criteria.

## Key documents

| File | What it holds |
| --- | --- |
| `docs/architecture.md` | Architecture overview: principles, components, tiers, deployment modes |
| `docs/architecture/` | Details: `components.md`, `crates.md`, `interfaces.md`, `data-flow.md`, `client-server.md`, `clients.md` |
| `docs/decisions.md` | Every decision made so far, with date and reason; open questions |
| `docs/roadmap.md` | Phases from skeleton to offline mode, with exit criteria |
| `docs/research/ai-tools-2026-10.md` | Model and library comparison behind the defaults |
| `docs/working-with-claude.md` | What Claude needs to work here and how to keep it efficient |

The full research write-up (with sources) is the Claude Doc
"AI tools for object recognition: research and recommendation":
https://claude.ai/artifact/Rv4iP4zssSm77xpLNVTxXm

## Architecture in one screen

Two tiers, three provider roles:

1. **`Locator`** (fast, on device, every frame): boxes the object under the pointer so
   the highlight is instant. Default: YOLO26n through the `ort` crate.
2. **`Describer`** (on request, through the gateway): names the object and writes the
   deeper description. Defaults: Gemini 3.8 Flash (identify), Gemini 4 Argon (details).
3. **`Enricher`** (reserved, not built yet): follow-up questions about an identified
   object, such as price. Topics get added over time.

Clients implement `FrameSource`, `PointerSource` and optionally `DepthSource`, and hand
them to `rev-engine`, the client-side brain shared by every device (pointer to pixel,
focus, tracking, crops, device cache, menu state). The engine talks to a
`RecognitionService`: `rev-remote` over WebSocket to `rev-gateway` (default), or
`rev-router` in the same process (desktop dev). The gateway (axum) holds API keys and runs
the router, which runs provider chains with fallback, budget and cache. Clients that do not
embed the engine can call the gateway protocol directly. Details:
`docs/architecture.md` and `docs/architecture/`.

## Planned workspace layout (not created yet)

```
crates/
  rev-core/               types and traits only; no vendor code, no I/O, no runtime
  rev-geometry/           camera model, ray to pixel, unprojection
  rev-imaging/            YUV to RGB, crop, resize, JPEG, sharpness, perceptual hash
  rev-prompts/            versioned prompts and JSON schemas
  rev-proto/              wire messages between clients and the gateway
  rev-router/             chains, fallback, budget, cache; implements RecognitionService
  rev-engine/             client brain: focus, tracking, crops, requests, view model
  rev-remote/             RecognitionService over WebSocket
  rev-ffi/                UniFFI bindings for Kotlin / Swift shells
  rev-testkit/            contract test suites, fixtures, fakes
adapters/
  rev-adapter-gemini/     rev-adapter-anthropic/   rev-adapter-openai/
  rev-adapter-ort/        (YOLO26n, RF-DETR Nano)  rev-adapter-moondream/ (offline, last)
apps/
  rev-gateway/            axum server; holds API keys; runs the router
  rev-desktop/            dev client: webcam, images, replay
  rev-quest/              Quest 3 / 3S OpenXR app (Android)
  rev-bench/              scoring harness
xtask/                    cargo xtask check-deps and dev commands
tests/fixtures/           golden images every adapter is scored on
```

Full table, dependency graph and feature flags: `docs/architecture/crates.md`.

`rev` = Recognize Everything VR. Keep this prefix for all crates.

## Rules that keep the design swappable

- Core owns the types. Adapters convert vendor formats (for example Gemini's
  `[ymin, xmin, ymax, xmax]` on 0..1000) into core types inside the adapter.
- All 2D coordinates are normalized to `0.0..=1.0`. Adapters return boxes relative to the
  image they were given (the crop); the router maps them to the frame.
- Prompts and JSON schemas live in `rev-prompts` (versioned); adapters map them to the
  vendor's structured-output feature.
- Dependency rules (`docs/architecture/crates.md`): `rev-core` depends on nothing in the
  workspace; adapters depend only on `rev-core`, `rev-prompts`, `rev-imaging`; the router
  and engine never depend on an adapter; only `apps/` (and `rev-ffi`) touch platform
  crates. `cargo xtask check-deps` enforces this in CI.
- The engine never knows where models run: it gets an `Arc<dyn RecognitionService>`.
- Dropping a stream cancels the request; frames are latest-wins, never queued.
- Each adapter is its own crate behind a Cargo feature; clients link only what they use.
- The router picks providers per role from config (ordered chain, fallback on timeout,
  error or rate limit) and logs latency and cost for every call.
- API keys live in the gateway or environment variables. Never in client code, never in
  git, never pasted into chat.
- `dyn` provider traits use `async-trait` (or `trait-variant`) for boxed futures.

## Rust conventions

- Stable toolchain, edition 2024. `cargo fmt` and `cargo clippy --all-targets -- -D warnings`
  must pass before a PR.
- Errors: `thiserror` in library crates, `anyhow` only in binaries and tests.
- Async runtime: `tokio`. HTTP: `reqwest` + `serde` (+ `schemars` for JSON schema).
- Prefer pure-Rust crates on device (`yuv`, `fast_image_resize`, `glam`, `imageproc`,
  `trackforge`). OpenCV is allowed only in the gateway or dev tools, behind a feature.
- Debug visualization: Rerun (`rerun` crate) in dev builds only.
- Tests: unit tests next to the code; adapter contract tests run against
  `tests/fixtures/`. Tests that call paid APIs are `#[ignore]` by default and need the
  API key in the environment.

## Commands

No Cargo workspace exists yet. Once it does:

```
cargo fmt --all
cargo clippy --all-targets -- -D warnings
cargo test --workspace
cargo xtask check-deps                                 # dependency rules
cargo ndk -t arm64-v8a build -p rev-quest --release    # Quest, needs Android NDK
```

## Platform facts worth remembering

- Quest 3 / 3S have **no eye tracking**. "Gaze" means head gaze (ray from the center of
  view). Real eye gaze is an optional input for devices that have it.
- Camera: Meta Passthrough Camera API (Horizon OS v74+), Android Camera2,
  `horizonos.permission.HEADSET_CAMERA`, up to 1728x1728 at 60 Hz, YUV420,
  20 to 40 ms capture latency. The camera sees less than the user's full view.
- The Quest NPU is not documented for third-party apps. Plan for GPU (Vulkan) and CPU.
- Licensing: the app will be open source. YOLO26 / YOLOE-26 are AGPL-3.0, so if they are
  bundled the app as a whole ships under AGPL-3.0 terms. RF-DETR (Apache 2.0) is the
  fallback.

## How to work with the owner (Arman)

- Ask for an explicit "yes" in chat before sending messages to anyone, submitting
  forms, buying anything, deleting files, or editing OS base files (`/windows`, `/linux`).
- Never type passwords, card numbers or ID numbers.
- Branch, commit, push and open PRs freely; never merge or push to `main` directly.
- Keep PRs small and focused on one goal. Update `docs/decisions.md` in the same PR when
  a decision changes.
- Do not mock paid API results to make something look finished. If a key or device is
  missing, say what is missing and continue with the parts that do not need it.
