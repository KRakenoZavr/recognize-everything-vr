# Roadmap

Each phase ends with something we can run and measure. Phases are ordered; later ones can
be reordered when we learn more. Crate names follow `docs/architecture/crates.md`.

## Phase 0: Skeleton (now)

- [x] Research AI tools and pick defaults
- [x] Architecture, decisions, roadmap, CLAUDE.md
- [x] Full architecture: components, crates, interfaces, data flow, protocol, clients
      (`docs/architecture/`, proposed 2026-10-25)
- [ ] Confirm the proposed architecture decisions in `docs/decisions.md`
- [ ] Cargo workspace per `docs/architecture/crates.md`: `rev-core` with the types and traits
      from `docs/architecture/interfaces.md`, every other crate empty but compiling
- [ ] `cargo xtask check-deps` enforcing the dependency rules
- [ ] CI on GitHub Actions: fmt, clippy `-D warnings`, test, `check-deps`, `cargo deny`
- [ ] Pick the project license

Exit: `cargo test --workspace` and `cargo xtask check-deps` pass in CI on an empty but
compiling workspace.

## Phase 1: Cloud spike on the desktop

- `rev-proto` (messages, MessagePack and JSON) and `rev-prompts` (identify and details
  prompts with schemas)
- `rev-adapter-gemini` implementing `Describer` with structured JSON output and streaming
- `rev-router` with the identify and details chains, timeouts, fallback, cost log
- `rev-gateway` with `/v1/session` (WebSocket) and `/v1/ask` (REST), static tokens
- `rev-remote`, and a minimal `rev-engine`: pixel pointer, crop window, request manager,
  menu model
- `rev-imaging`: crop, resize, JPEG, perceptual hash
- `rev-desktop`: webcam or image file, click to point, menu panel, timings panel

Exit: click an object on a webcam frame and see a name and description; latency per stage
and cost logged.

## Phase 2: Scoring harness

- 50 to 100 photos of real objects in `tests/fixtures/` with expected names
- `rev-testkit` contract suites every adapter must pass
- `rev-bench`: accuracy, latency and cost per adapter
- Second and third adapters: `rev-adapter-anthropic`, `rev-adapter-openai`

Exit: a table comparing adapters on our own images; defaults confirmed or changed.

## Phase 3: Quest 3 client, cloud only

- Spike first: Bevy + `bevy_mod_openxr` showing passthrough, a hand ray and a world-space
  text panel at 90 Hz. If it cannot, switch to raw `openxr` + `wgpu`
- `rev-quest` built with `cargo-ndk`: passthrough camera frames through Android Camera2,
  camera intrinsics and pose, timestamps mapped to `XrTime`
- `rev-geometry`: ray to pixel with the Depth API, unprojection for world anchors
- Hand ray and head gaze pointers, pinch to ask, menu panel anchored in 3D
- Recording and replay, so later work can run on the desktop

Exit: on a Quest 3, pinch at an object and get the menu in under 2 s to the first line.

## Phase 4: On-device Locator

- Benchmark YOLO26n and RF-DETR Nano on Quest 3 (`ort` on CPU, Burn on the Vulkan GPU)
- `rev-adapter-ort` implementing `Locator`
- Tracker (`trackforge`), focus selector with hysteresis, device cache keyed by track id
- Live highlight under the pointer

Exit: highlight follows the pointed object at under 100 ms; repeat questions hit the cache.

## Phase 5: Enricher

- Implement the reserved `Enricher` role, price first
- A model with a web-search tool behind the trait; answers carry sources
- Follow-up buttons in the menu, driven by the topics the gateway advertises

Exit: ask "how much is this?" about an identified object and get a sourced answer.

## Phase 6: More clients

- `rev-ffi` (UniFFI bindings of `rev-engine`)
- Android phone or tablet client: Kotlin shell with CameraX and tap to point
- Optional: devices with real eye tracking

Exit: the same gateway serves Quest and phone clients without changes to core.

## Phase 7: Offline mode (last)

- `rev-adapter-moondream` running Moondream 3.1 on a local GPU machine
- Gateway configuration that uses no cloud vendor

Exit: the full flow works with the internet disconnected (local network only).
