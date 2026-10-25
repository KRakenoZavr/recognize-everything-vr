# AI tools for object recognition (research, October 2026)

Summary of the research behind the defaults in `docs/decisions.md`. The full write-up with
diagrams and every source is the Claude Doc
https://claude.ai/artifact/Rv4iP4zssSm77xpLNVTxXm (as of 2026-10-24).

Models change monthly. Re-check scores and prices before relying on them, and prefer our
own scoring harness (roadmap phase 2) over public benchmarks.

## Hosted vision LLMs (`Describer`)

Scores from [Roboflow Vision Evals](https://playground.roboflow.com/evals), 63 models,
last run 2026-10-13, low-effort runs. Cost and time are per benchmark sample; our short
"identify this crop" calls should be faster, but are not measured yet.

| Model | Overall | Detect | Identify | Reason | Cost per call | Time per call | Role |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Gemini 4 Argon | 87.5% (#1) | 82.5% | 93.8% | 89.4% | $0.0058 | 13.4 s | Default for details |
| Claude Opus 5.5 | 82.0% (#3) | 74.5% | 93.8% | 83.0% | $0.015 | 7.6 s | Alternative vendor |
| GPT-6.1 Sol | 81.7% (#5) | 80.8% | 89.6% | 83.7% | $0.0068 | 12.8 s | Alternative vendor |
| Gemini 3.8 Flash | 79.8% (#7) | 68.1% | 97.9% | 81.2% | $0.0045 | 12.8 s | Default for identify |
| Claude Sonnet 5.5 | 77.6% (#10) | 74.3% | 91.7% | 76.4% | $0.0073 | 8.3 s | Cheaper Claude option |
| GPT-5.6 Luna | 64.7% (#29) | 61.0% | 83.3% | 60.5% | $0.0011 | 8.6 s | Budget fallback |
| Qwen3.8 Flash | 59.7% | 59.8% | 88.5% | 35.1% | $0.0004 | 7.3 s | Cheapest, weak reasoning |

Token prices per 1M input / output: Gemini 3.8 Flash $0.825 / $4.13; Gemini 4 Argon $2 / $10
at launch ($4 / $20 list); Claude Opus 5.5 $4 / $20; Claude Sonnet 5.5 $2 / $10;
GPT-6.1 Sol $2 / $10; GPT-5.6 Luna $0.20 / $1.20.

Notes:

- Gemini's vision API returns `box_2d` as `[ymin, xmin, ymax, xmax]` scaled to 0..1000,
  plus segmentation polygons. Google advises minimal thinking for segmentation. An image
  costs 258 tokens per 768x768 tile.
- No vendor ships an official Rust SDK. Adapters are thin `reqwest` + `serde` clients using
  each vendor's JSON-schema structured output.

## On-device and edge detectors (`Locator`)

Speeds are the vendors' desktop figures; Quest numbers need our own benchmark.

| Model | What it does | Size | Accuracy | Vendor speed | License |
| --- | --- | --- | --- | --- | --- |
| YOLO26n | 80 COCO classes, NMS-free head | 2.4M params | 40.9 mAP COCO | 38.9 ms x86 CPU (ONNX), 1.7 ms T4 | AGPL-3.0 or Enterprise |
| YOLO26s | Same, larger | 9.5M params | 48.6 mAP COCO | 87.2 ms x86 CPU | AGPL-3.0 or Enterprise |
| YOLOE-26 | Open vocabulary: text, visual or no prompt | x size largest | 40.6 AP LVIS (x, text prompts) | not published per size | AGPL-3.0 or Enterprise |
| RF-DETR Nano | COCO classes, fine-tunable; seg variant | 30.5M params | 48.4 AP COCO at 384 px | 2.3 ms T4 (TensorRT FP16) | Apache 2.0 |
| YOLOv9 (Meta sample) | 80 COCO classes, uint8 | not stated | not stated | runs on Quest 3 | sample code |
| SAM 3 | Segments anything matching a text concept | not stated | not stated | server GPU | custom |
| Moondream 3.1 | Small VLM: query, caption, detect, point, segment | 9B total, 2B active | not ranked | about 10 GB VRAM | Moondream License |

## Rust ecosystem

| Need | Recommended | Alternatives |
| --- | --- | --- |
| Run detectors | `ort` 2.0 (ONNX Runtime; rc.15, 2026-10-19) | Burn 0.22 (pure Rust, Vulkan GPU, imports ONNX), tract |
| Native Rust models | Candle (YOLOv8, SAM, Moondream, DINOv2, CLIP examples) | Burn |
| Hosted LLM calls | `reqwest` + `serde` + `schemars` | `async-openai` (community) |
| XR shell on Quest | `openxr` crate, or Bevy + `bevy_mod_xr` 0.6 (Bevy 0.19) | Godot with Rust bindings |
| Camera on Quest | Android NDK Camera2 via `ndk` / `ndk-sys` | JNI to Java Camera2 |
| Gateway server | `axum` + `tokio` | `actix-web` |

`ort`'s prebuilt binaries do not include NNAPI or QNN. The Quest NPU is not documented for
third-party apps, so plan for CPU and GPU.

## OpenCV and other classic CV libraries

OpenCV fits the plumbing around the models, not the recognition. Pure-Rust crates cover the
headset; OpenCV stays optional in the gateway and dev tools.

| Job | Pure-Rust pick | OpenCV equivalent |
| --- | --- | --- |
| YUV420 to RGB | `yuv` (yuvutils-rs; NEON SIMD; BSD-3 or Apache-2.0) | `cvtColor` |
| Crop and resize | `fast_image_resize`, kornia-rs | `resize` |
| Project the hand ray into a pixel | `glam` + our own pinhole model | `calib3d` |
| Keep the highlight steady | `trackforge` 0.4 (ByteTrack, SORT, OC-SORT; MIT) | tracking module |
| Optical flow | none mature | `video` module (only gap) |
| Skip blurry crops | `imageproc` 0.27 filters | Laplacian variance |
| Perceptual hash for the cache | `imageproc::image_hash` | `img_hash` (contrib) |
| Debug visualization | Rerun (Rust SDK) | `highgui` |
| Hand tracking on phones | MediaPipe Hand Landmarker (Android, via JNI) | none |

Why not OpenCV on the Quest: the `opencv` crate (0.100) needs a system OpenCV and
`libclang` and does not document Android; official OpenCV 5.0.0 for Android is 303 MB;
opencv-mobile is 25 MB but drops `dnn` and `calib3d`.

## Quest 3 / 3S platform facts

- Passthrough Camera API: Horizon OS v74+, Quest 3 and 3S only, Android Camera2,
  `horizonos.permission.HEADSET_CAMERA`; 1280x960, 1280x1280 (v83+) or 1728x1728 (v209+)
  at 60 Hz, YUV420; 20 to 40 ms capture latency; about 1 to 2% GPU and 45 MB per stream.
- No eye tracking on Quest 3 / 3S; hand tracking through OpenXR.
- Meta's object detection sample places labels in 3D by raycasting the box center against
  the Depth API's environment depth.
- Camera images count as Device User Data under Meta's developer data policy.
