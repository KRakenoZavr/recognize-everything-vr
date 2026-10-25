# Interfaces

Status: proposed, 2026-10-25. The types and traits that every other crate builds on.

The `rev-core` and `rev-engine` sketches below were compiled and tested in a scratch crate
(Rust 1.97, edition 2024, `cargo clippy -D warnings` clean) on 2026-10-25, including a test
that uses every trait as `dyn`. Derives are left out for readability: core types derive
`Clone`, `Debug`, `Serialize` and `Deserialize` unless they hold an `Arc` or a stream.

## Conventions

### Coordinates

- **2D is normalized**: `0.0..=1.0`, origin at the top-left, x to the right, y down, relative
  to the image the value belongs to.
- **Frame space is the default.** Everything that leaves the router or the engine is
  relative to the frame. Adapters return boxes relative to the image they were given (the
  crop); the router maps them with `BBox::to_parent(crop_in_frame)`.
- **Vendor formats stop at the adapter.** Gemini's `box_2d` (`[ymin, xmin, ymax, xmax]` on
  0..1000), pixel boxes from other vendors and YOLO's center-size boxes are converted inside
  the adapter.
- **3D** is meters in the client's tracking space, right-handed, +Y up, -Z forward (the
  OpenXR convention). Only `rev-geometry`, `rev-engine` and clients read 3D values; the
  gateway never sees them.

### Time

`Timestamp` is nanoseconds on the client's monotonic clock (`XrTime` on Quest). It is only
compared with timestamps from the same client. The gateway never interprets it.

### Errors

| Error | Router: try next provider? | Retry the same provider? |
| --- | --- | --- |
| `Timeout` | yes | no |
| `RateLimited { retry_after }` | yes | after `retry_after`, only if nothing else is left |
| `Unavailable` (network, 5xx) | yes | once, with jitter, if nothing else is left |
| `BadResponse` (schema broken) | yes | no |
| `Rejected` (4xx, auth, refusal) | yes, and log an alert for auth errors | no |
| `Unsupported` (asked for something it cannot do) | yes, silently | no |

`thiserror` in libraries, `anyhow` only in binaries and tests (unchanged from CLAUDE.md).

### Streaming and cancellation

- Provider and service methods are `async fn ... -> Result<Stream, Error>`. An error before
  the stream exists lets the router fall back cleanly.
- If a stream fails after it produced events, the router keeps what arrived, and the next
  provider is asked for the rest (for example details after a good identity). The identity
  is never replaced mid-answer.
- **Dropping a stream cancels the work.** Adapters stop reading and the HTTP request is
  aborted; across the network `rev-remote` sends `Cancel`.

### Async traits

Provider traits use `async-trait` so they work as `Arc<dyn Trait>`: native `async fn` in
traits is not `dyn`-compatible on stable (checked on Rust 1.97, 2026-10-25). Revisit when
it is.

### Extensibility

`Topic` is `#[non_exhaustive]` with an `Other(String)` variant, so follow-up topics can be
added without breaking anything. Protocol messages are additive: new optional fields and
new message types only within one protocol version.

## rev-core

### Geometry and time

```rust
pub mod geom {
    /// Normalized image coordinates: (0, 0) top-left, (1, 1) bottom-right.
    pub struct Point2 { pub x: f32, pub y: f32 }

    /// Axis-aligned box in normalized image coordinates.
    pub struct BBox { pub x0: f32, pub y0: f32, pub x1: f32, pub y1: f32 }

    impl BBox {
        pub const FULL: BBox = BBox { x0: 0.0, y0: 0.0, x1: 1.0, y1: 1.0 };
        /// `self` is relative to `outer` (a crop); returns it relative to the frame.
        pub fn to_parent(self, outer: BBox) -> BBox { /* ... */ }
        pub fn center(self) -> Point2 { /* ... */ }
    }

    /// Plain arrays keep core free of a math crate version (Bevy pins its own
    /// glam); rev-geometry converts to glam.
    pub struct Pose { pub position: [f32; 3], pub orientation: [f32; 4] /* x y z w */ }
    pub struct Ray3 { pub origin: [f32; 3], pub dir: [f32; 3] /* unit */ }
}

pub mod time {
    /// Nanoseconds on the client's monotonic clock (XrTime on Quest).
    pub struct Timestamp(pub i64);
}
```

### Images and frames

```rust
pub mod image {
    pub struct Image { pub width: u32, pub height: u32, pub pixels: Pixels }

    pub enum Pixels {
        Rgb8 { data: Bytes, row_stride: u32 },
        /// Android Camera2 YUV_420_888 as delivered; rev-imaging converts it.
        Yuv420 { y: Plane, u: Plane, v: Plane },
        Jpeg(Bytes),
    }

    pub struct Plane { pub data: Bytes, pub row_stride: u32, pub pixel_stride: u32 }
}

pub mod frame {
    pub struct FrameId(pub u64);

    pub struct Frame {
        pub id: FrameId,
        pub captured_at: Timestamp,
        pub image: Image,
        /// Present when the client knows where the camera was (Quest, ARCore).
        pub camera: Option<CameraModel>,
    }

    pub struct CameraModel {
        pub intrinsics: Intrinsics,
        /// Camera pose in tracking space at `captured_at`.
        pub pose: Pose,
    }

    /// Pinhole model in pixels of the frame's image.
    pub struct Intrinsics { pub fx: f32, pub fy: f32, pub cx: f32, pub cy: f32, pub distortion: Distortion }

    pub enum Distortion {
        None,
        BrownConrady { k1: f32, k2: f32, p1: f32, p2: f32, k3: f32 },
    }
}
```

`Bytes` (from the `bytes` crate) makes images cheap to clone and hand to the network layer
without copying.

### Input

```rust
pub mod input {
    pub enum Hand { Left, Right }

    pub enum PointerKind {
        HandRay(Hand),
        Controller(Hand),
        /// Ray from the center of view. What "gaze" means on Quest 3 / 3S.
        HeadGaze,
        /// Only on devices with eye-tracking hardware.
        EyeGaze,
        Touch,
        Mouse,
    }

    pub enum PointerTarget {
        /// Already a point in the frame (phone tap, mouse click).
        Pixel(Point2),
        /// A ray in tracking space (hand, controller, head or eye gaze).
        Ray(Ray3),
    }

    pub struct PointerSample { pub at: Timestamp, pub kind: PointerKind, pub target: PointerTarget }

    /// What the user wants. Clients map pinch, tap, click, dwell or voice to it.
    pub enum Intent {
        Ask,
        Dismiss,
        Retry,
        /// Reserved for the Enricher role.
        FollowUp { topic: Topic, question: Option<String> },
    }

    pub struct IntentEvent { pub at: Timestamp, pub intent: Intent }
}
```

### Results

```rust
pub mod insight {
    pub struct TrackId(pub u64);
    pub struct Label { pub text: String, pub class_id: Option<u32> }

    pub enum Mask {
        Polygon(Vec<Point2>),
        Bitmap { width: u32, height: u32, data: Bytes },
    }

    /// Output of a Locator. Relative to the frame.
    pub struct Detection {
        pub bbox: BBox,
        pub mask: Option<Mask>,
        pub label: Option<Label>,
        pub score: f32,
        pub track_id: Option<TrackId>,
    }

    /// The fast answer: what the object is. The menu title.
    pub struct Identity {
        pub name: String,
        pub category: String,
        pub confidence: f32,
        /// Relative to the frame once it leaves the router.
        pub bbox: Option<BBox>,
        pub mask: Option<Mask>,
    }

    pub struct Property {
        /// Stable snake_case key, for example "material".
        pub key: String,
        /// Display label in the request locale.
        pub label: String,
        pub value: PropertyValue,
        pub source: Source,
    }

    pub enum PropertyValue {
        Text(String),
        Number { value: f64, unit: Option<String> },
        Range { min: f64, max: f64, unit: Option<String> },
        Bool(bool),
    }

    pub enum Source {
        Model(ProviderId),
        Web { title: String, url: String },
    }

    pub struct InsightId(pub u128);

    /// Everything the context menu shows about one object.
    pub struct ObjectInsight {
        pub id: InsightId,
        pub identity: Identity,
        pub summary: String,
        pub properties: Vec<Property>,
        pub provenance: Vec<Provenance>,
    }

    /// Which provider produced which part: for debugging, cost and the UI.
    pub struct Provenance {
        pub role: Role,
        pub provider: ProviderId,
        pub model: String,
        pub prompt_version: u32,
        pub latency_ms: u32,
        pub usage: Usage,
    }
}
```

### Providers

```rust
pub mod provider {
    pub struct ProviderId(pub String);
    pub struct RequestId(pub u64);
    /// BCP 47 language tag, for example "en-US".
    pub struct Locale(pub String);

    pub enum Role { Locate, Identify, Details, Enrich }
    pub enum Runs { OnDevice, LocalServer, Cloud }

    pub struct ProviderInfo {
        pub id: ProviderId,
        pub model: String,
        pub runs: Runs,
        pub capabilities: Capabilities,
    }

    pub struct Capabilities {
        pub open_vocabulary: bool,
        pub boxes: bool,
        pub masks: bool,
        pub properties: bool,
        pub streaming: bool,
        pub web_sources: bool,
    }

    /// Measured by the adapter; cost comes from the price table in config.
    pub struct Usage {
        pub input_tokens: u32,
        pub output_tokens: u32,
        pub images: u32,
        pub cost_micro_usd: u64,
    }

    #[derive(thiserror::Error)]
    pub enum ProviderError {
        Timeout,
        RateLimited { retry_after: Option<Duration> },
        Unavailable(String),   // network error, HTTP 5xx
        BadResponse(String),   // unparsable, or breaks the schema
        Rejected(String),      // HTTP 4xx, auth failure, safety refusal
        Unsupported(String),
    }

    pub type EventStream<T> = Pin<Box<dyn Stream<Item = Result<T, ProviderError>> + Send>>;
```

#### Locator

```rust
    pub struct LocateRequest {
        pub frame: Arc<Frame>,
        /// Only objects near this point matter; lets adapters crop first.
        pub focus: Option<Point2>,
        pub max_results: u16,
        /// Text prompts for open-vocabulary models (YOLOE-26). None = default classes.
        pub classes: Option<Vec<String>>,
    }

    #[async_trait]
    pub trait Locator: Send + Sync {
        fn info(&self) -> &ProviderInfo;
        async fn locate(&self, req: LocateRequest) -> Result<Vec<Detection>, ProviderError>;
    }
```

On device the adapter runs inference on its own thread and the async method only awaits
the result, so the engine's runtime is never blocked.

#### Describer

```rust
    pub enum Detail {
        /// Name, category, confidence, refined box. Short and fast.
        Identify,
        /// Summary and properties, streamed.
        Full,
    }

    pub struct DescribeRequest {
        pub crop: Image,
        pub crop_in_frame: BBox,
        /// Downscaled frame with the target outlined, for context.
        pub context: Option<Image>,
        pub hint: Option<Label>,
        /// Set for `Detail::Full` when the identify stage already ran.
        pub identity: Option<Identity>,
        pub detail: Detail,
        pub locale: Locale,
    }

    pub enum DescribeEvent {
        /// Box relative to the crop; the router maps it to the frame.
        Identity(Identity),
        SummaryDelta(String),
        Property(Property),
        Usage(Usage),
    }

    #[async_trait]
    pub trait Describer: Send + Sync {
        fn info(&self) -> &ProviderInfo;
        /// Errors before the first event allow a clean fallback.
        /// The stream ends when the answer is complete.
        async fn describe(&self, req: DescribeRequest)
            -> Result<EventStream<DescribeEvent>, ProviderError>;
    }
```

One trait covers both stages because some models are good at both; the router decides which
provider runs which stage. An adapter that cannot do a stage returns `Unsupported`.

#### Enricher (reserved)

```rust
    #[non_exhaustive]
    pub enum Topic {
        Price,
        /// Topics added later without a breaking change.
        Other(String),
    }

    pub struct EnrichRequest {
        pub object: ObjectInsight,
        pub topic: Topic,
        /// Free text, for example "how much is this used?".
        pub question: Option<String>,
        pub locale: Locale,
        /// ISO 3166-1 country, for prices and currency.
        pub region: Option<String>,
        pub crop: Option<Image>,
    }

    pub enum EnrichEvent {
        TextDelta(String),
        Fact(Property),
        Source { title: String, url: String },
        Usage(Usage),
    }

    #[async_trait]
    pub trait Enricher: Send + Sync {
        fn info(&self) -> &ProviderInfo;
        fn topics(&self) -> &[Topic];
        async fn enrich(&self, req: EnrichRequest)
            -> Result<EventStream<EnrichEvent>, ProviderError>;
    }
}
```

### The service the engine talks to

```rust
pub mod service {
    pub enum DetailsMode {
        /// Identify only; details when the user expands the menu.
        OnExpand,
        /// Details start when the identity arrives (default).
        AfterIdentify,
        /// Both stages start at once. Faster, costs more.
        Parallel,
    }

    /// One "what is this?" from the user.
    pub struct AskRequest {
        pub id: RequestId,
        pub crop: Image,
        pub crop_in_frame: BBox,
        pub context: Option<Image>,
        pub hint: Option<Label>,
        pub locale: Locale,
        pub details: DetailsMode,
        /// Skip identify: details for an identity the client already has
        /// (menu expanded after `OnExpand`, or a cache hit on the device).
        pub known: Option<Identity>,
    }

    pub enum InsightEvent {
        Identity(Identity),
        SummaryDelta(String),
        Property(Property),
        Provenance(Provenance),
        /// Last event: the assembled answer, also what gets cached.
        Done(ObjectInsight),
    }

    pub struct ServiceCapabilities {
        pub protocol_version: u16,
        pub topics: Vec<Topic>,          // empty until an Enricher is configured
        pub max_image_bytes: u32,
        pub budget: Option<BudgetStatus>,
    }

    pub struct BudgetStatus { pub spent_micro_usd: u64, pub limit_micro_usd: u64 }

    #[derive(thiserror::Error)]
    pub enum ServiceError {
        NoProvider { attempts: Vec<(ProviderId, ProviderError)> },
        BudgetExceeded,
        RateLimited { retry_after: Option<Duration> },
        Unauthorized,
        Transport(String),
        Protocol(String),
    }

    pub type ServiceStream<T> = Pin<Box<dyn Stream<Item = Result<T, ServiceError>> + Send>>;

    /// Implemented in process by rev-router and over the network by rev-remote,
    /// so the engine cannot tell where the models run. Dropping a stream cancels.
    #[async_trait]
    pub trait RecognitionService: Send + Sync {
        async fn capabilities(&self) -> Result<ServiceCapabilities, ServiceError>;
        async fn ask(&self, req: AskRequest) -> Result<ServiceStream<InsightEvent>, ServiceError>;
        async fn enrich(&self, req: EnrichRequest) -> Result<ServiceStream<EnrichEvent>, ServiceError>;
    }
}
```

The service takes an `AskRequest` (what the user wants) while a `Describer` takes a
`DescribeRequest` (one stage). The router turns the first into one or two of the second.

### Client sources

```rust
pub mod source {
    pub struct CameraInfo {
        pub width: u32,
        pub height: u32,
        pub fps: f32,
        pub intrinsics: Option<Intrinsics>,
    }

    /// A camera, a video file or a recording. Latest frame wins.
    pub trait FrameSource: Send + Sync {
        fn camera(&self) -> CameraInfo;
        /// Never blocks. None until the first frame arrives.
        fn latest(&self) -> Option<Arc<Frame>>;
    }

    /// Hand ray, head gaze, eye gaze, tap or click.
    pub trait PointerSource: Send + Sync {
        /// The pointer as it was at `at`. Camera frames are 20 to 40 ms old on
        /// arrival, so the engine asks for the pointer at capture time.
        fn sample_at(&self, at: Timestamp) -> Option<PointerSample>;
    }

    /// Real-world depth along a ray (Quest Depth API, ARCore depth).
    pub trait DepthSource: Send + Sync {
        /// Meters along `ray` to the first real surface, if known.
        fn raycast(&self, ray: Ray3, at: Timestamp) -> Option<f32>;
    }
}
```

These are synchronous on purpose: the shell fills them from its own threads (camera
callback, XR frame loop) and the engine only reads the latest value.

## rev-engine public API

What a shell sees. Everything inside the engine is private.

```rust
pub struct EngineConfig {
    pub locale: Locale,
    pub region: Option<String>,
    pub details: DetailsMode,
    pub crop: CropConfig,
    pub focus: FocusConfig,
    /// 0 disables the Locator even when one is provided.
    pub locator_fps: f32,
}

pub struct CropConfig {
    pub pad: f32,                    // around a detection box, fraction of its size (0.15)
    pub min_side_px: u32,            // smaller boxes grow to this (224)
    pub window_without_locator: f32, // square around the pointer, fraction of short side (0.35)
    pub context_long_side_px: u32,   // (768)
    pub jpeg_quality: u8,            // (85)
}

pub struct FocusConfig {
    pub switch_after: Duration,      // pointer must rest on a new object this long (150 ms)
    pub keep_lost_for: Duration,     // focus survives a lost track this long (300 ms)
}

/// Everything platform-specific, as trait objects.
pub struct Inputs {
    pub frames: Arc<dyn FrameSource>,
    pub pointer: Arc<dyn PointerSource>,
    pub depth: Option<Arc<dyn DepthSource>>,
    pub locator: Option<Arc<dyn Locator>>,
    pub service: Arc<dyn RecognitionService>,
}

/// Starts the engine's tasks on `rt` and returns a handle.
pub fn spawn(cfg: EngineConfig, inputs: Inputs, rt: &tokio::runtime::Handle) -> EngineHandle;

#[derive(Clone)]
pub struct EngineHandle { /* mpsc sender for intents, watch receiver for the view */ }

impl EngineHandle {
    /// Pinch, tap, click, dwell or voice, already mapped to an intent.
    pub fn send(&self, ev: IntentEvent);
    /// Latest view. Cheap; the render loop calls it once per frame.
    pub fn view(&self) -> Arc<ViewState>;
    /// For event-driven UIs (desktop): resolves when the view changes.
    pub async fn changed(&mut self) -> bool;
}

/// What the renderer draws this frame.
pub struct ViewState {
    pub reticle: Option<Reticle>,
    pub highlight: Option<Highlight>,
    pub menu: Option<MenuModel>,
}

/// Where something sits: always in the image, and in the world when the
/// client has a camera pose and depth (Quest).
pub struct Anchor {
    pub frame: FrameId,
    pub image: BBox,
    pub world: Option<[f32; 3]>,
    pub distance_m: Option<f32>,
}

pub struct Reticle {
    pub kind: PointerKind,
    pub at: Option<Point2>,
    /// False when the pointer aims outside what the camera sees.
    pub in_camera_view: bool,
}

pub enum HighlightSource {
    Locator,
    /// Box returned by the identify stage when there is no Locator (cloud first).
    Identity,
}

pub struct Highlight {
    pub anchor: Anchor,
    pub mask: Option<Mask>,
    pub track: Option<TrackId>,
    pub label: Option<String>,
    pub source: HighlightSource,
}

/// The context menu as data. Each client renders it its own way.
pub struct MenuModel {
    pub request: RequestId,
    pub anchor: Anchor,
    pub state: MenuState,
    pub title: Option<String>,
    pub category: Option<String>,
    pub confidence: Option<f32>,
    pub summary: String,
    pub properties: Vec<Property>,
    pub actions: Vec<MenuAction>,
    pub follow_ups: Vec<FollowUpSection>,
}

pub enum MenuState {
    Asking,
    Identified,
    Detailing,
    Complete,
    Failed { message: String, retryable: bool },
}

pub enum MenuAction {
    Close,
    Retry,
    MoreDetails,
    /// Shown only when the service advertises the topic (Enricher).
    FollowUp(Topic),
}

pub struct FollowUpSection {
    pub topic: Topic,
    pub text: String,
    pub facts: Vec<Property>,
    pub sources: Vec<(String, String)>, // title, url
    pub done: bool,
}
```

The numbers in brackets are starting defaults, to be tuned on real recordings.

`rev-ffi` exposes the same API to Kotlin and Swift: `FrameSource`, `PointerSource` and
`DepthSource` become UniFFI callback interfaces, and `ViewState` a record the UI polls.

## rev-router public API (sketch, not compiled yet)

```rust
pub struct Router { /* chains per stage, registry, cache, budget, metrics */ }

impl Router {
    pub fn from_config(cfg: RouterConfig, registry: &Registry) -> Result<Router, ConfigError>;
}

#[async_trait]
impl RecognitionService for Router { /* ask, enrich, capabilities */ }

/// Adapter name -> constructor. Filled by the app (see crates.md).
#[derive(Default)]
pub struct Registry { /* ... */ }

impl Registry {
    pub fn locator(&mut self, adapter: &'static str, f: impl Fn(toml::Value) -> Result<Arc<dyn Locator>, ConfigError> + 'static);
    pub fn describer(&mut self, adapter: &'static str, f: impl Fn(toml::Value) -> Result<Arc<dyn Describer>, ConfigError> + 'static);
    pub fn enricher(&mut self, adapter: &'static str, f: impl Fn(toml::Value) -> Result<Arc<dyn Enricher>, ConfigError> + 'static);
}

/// Who is asking, for budgets, rate limits and cache scope. Set by the gateway
/// from the auth token; a fixed local caller in embedded mode.
pub struct Caller { pub id: String }
```

`Router` is created per process; the gateway wraps it per connection with the `Caller`
(`router.for_caller(caller) -> impl RecognitionService`).

The wire protocol (`rev-proto`) is described in
[client-server.md](client-server.md#wire-protocol).
