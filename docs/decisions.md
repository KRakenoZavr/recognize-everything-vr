# Decisions

Newest first. When a decision changes, add a new entry and mark the old one as replaced.
Status is `Proposed` until Arman confirms it, then `Active`.

| Date | Decision | Why | Status |
| --- | --- | --- | --- |
| 2026-10-25 | Workspace layout `crates/`, `adapters/`, `apps/`, `xtask/`. The draft's single `rev-pipeline` is split into `rev-engine` (client side: focus, tracking, crops, menu state) and `rev-router` (server side: chains, fallback, budget, cache); new crates `rev-geometry`, `rev-imaging`, `rev-prompts`, `rev-proto`, `rev-remote`, `rev-ffi`, `rev-testkit`, `rev-bench`. Replaces the 2026-10-24 layout in CLAUDE.md. | The gateway should not compile client code, the headset should not compile vendor HTTP clients, and each crate gets one job. See `docs/architecture/crates.md`. | Proposed |
| 2026-10-25 | The engine talks to one `RecognitionService` trait with two implementations: `rev-router` in process and `rev-remote` over the network. | The engine never knows where models run, so cloud, local gateway and offline modes need no engine changes. | Proposed |
| 2026-10-25 | Dependency rules (core depends on nothing; adapters only on core, prompts and imaging; router and engine never on adapters; platform crates only in `apps/`) are enforced by `cargo xtask check-deps` in CI. | Rules that are not checked erode. | Proposed |
| 2026-10-25 | Wire protocol: one WebSocket session per client at `/v1/session`, MessagePack in binary frames (JSON for debugging and web), requests multiplexed by id, `Cancel` message. REST `/v1/ask` with NDJSON or SSE for simple clients. | One open connection avoids a TLS handshake per pinch, supports cancel and streaming; raw image bytes avoid base64 overhead. Round trip tested in a scratch crate. | Proposed |
| 2026-10-25 | `Describer` runs in two stages with separate chains: identify (fast) then details (streamed). Default `DetailsMode::AfterIdentify`; `Parallel` and `OnExpand` available. | The name shows in under 2 s while the stronger model writes the details. | Proposed |
| 2026-10-25 | Quest shell: Bevy with `bevy_mod_openxr`, confirmed by a phase 3 spike (passthrough, hand ray, world-space text at 90 Hz). Fallback: raw `openxr` + `wgpu`. | Bevy brings rendering, world-space UI and Quest passthrough support; the spike guards against performance or version risk. | Proposed |
| 2026-10-25 | On Quest, the pointer is the hand aim ray by default with head gaze as fallback; pinch asks in both modes. Rays become pixels through a Depth API hit projected into the camera, with line-sweep and fixed-distance fallbacks. | A hand ray only becomes a point in the image once we know where it hits the world. | Proposed |
| 2026-10-25 | Non-Rust shells (Android in Kotlin, iOS in Swift) embed `rev-engine` through UniFFI (`rev-ffi`); any other device can be a protocol-only client. Phone client: Kotlin + CameraX + `rev-ffi`. | Native phone UI and camera handling, with the shared engine as the common value. | Proposed |
| 2026-10-25 | Camera images are never stored by the gateway or written to logs; caches hold finished answers keyed by perceptual hash, not images. | Privacy, and Meta's Device User Data policy for passthrough camera images. | Proposed |
| 2026-10-24 | OpenCV is optional: allowed in the gateway and dev tools behind a Cargo feature, not on the headset. Pure-Rust crates (`yuv`, `fast_image_resize`, `glam`, `imageproc`, `trackforge`, Rerun) cover device-side plumbing. | The Rust `opencv` crate does not document Android; official OpenCV for Android is a 303 MB package; the slim opencv-mobile build drops `dnn` and `calib3d`. | Active |
| 2026-10-24 | Context menu shows a deeper description only. A third role, `Enricher`, is reserved for follow-up questions (price first, more topics over time). | Owner wants the space designed in, but not built yet. | Active |
| 2026-10-24 | Sending camera crops to cloud vendors is acceptable. Offline mode (self-hosted Moondream 3.1) is the last roadmap phase. | Owner decision. | Active |
| 2026-10-24 | The app will be open source. AGPL-3.0 models (YOLO26, YOLOE-26) may ship, so YOLO26n stays the on-device default. | Owner decision. If bundled, the app as a whole ships under AGPL-3.0 terms. | Active |
| 2026-10-24 | First prototype is cloud-only: pinch, crop around the pointer, `Describer`, menu. The on-device `Locator` comes after a Quest 3 benchmark. | Fastest way to measure real end-to-end latency. | Active |
| 2026-10-24 | On-device `Locator` default: YOLO26n through the `ort` crate. Fallback: RF-DETR Nano (Apache 2.0). Later: YOLOE-26 for open vocabulary on device. | Lightest model with a documented ONNX export; Meta's own sample proves YOLO-class detection runs on Quest 3. | Active |
| 2026-10-24 | Hosted `Describer` default: Google Gemini through one adapter. Gemini 3.8 Flash for identify and locate, Gemini 4 Argon for details. Alternatives: Claude Opus 5.5 / Sonnet 5.5, GPT-6.1 Sol, GPT-5.6 Luna (budget). | Best accuracy for the cost on Roboflow Vision Evals (Oct 2026); Gemini documents box and mask output. See `docs/research/ai-tools-2026-10.md`. | Active |
| 2026-10-24 | Every AI model sits behind a Rust trait (`Locator`, `Describer`, reserved `Enricher`) and is chosen by config with fallback chains. | Swap tools when a better one is released without rewriting code. | Active |
| 2026-10-24 | On Quest 3 / 3S, "gaze" means head gaze. | These headsets have no eye-tracking hardware. | Active |
| 2026-10-24 | Architecture must not depend on the client: phone, tablet, webcam and headset all feed the same core. | Owner requirement. | Active |
| 2026-10-24 | First target device: Meta Quest 3 / 3S. | Owner decision. | Active |
| 2026-10-24 | Main language: Rust. | Owner decision. | Active |

## Open questions

- [ ] Monthly budget per user for the router to enforce.
- [ ] Project license file. AGPL-3.0 is the natural fit if YOLO26 is bundled.
- [ ] Exact Gemini model IDs and pricing at implementation time (Gemini 4 Argon launch
      pricing may end).
- [ ] Who runs the gateway and pays for model calls: self-hosted with your own keys, one
      hosted gateway, or both. Recommendation: self-hosting first, decide on a hosted
      gateway before a store release. Ties into the budget question. See
      `docs/architecture/client-server.md`.
- [ ] Quest shell: Bevy + `bevy_mod_openxr` or raw `openxr` + `wgpu` (phase 3 spike).
- [ ] Quest APK build: Gradle project with `cargo-ndk`, or `xbuild` (phase 3 spike).
