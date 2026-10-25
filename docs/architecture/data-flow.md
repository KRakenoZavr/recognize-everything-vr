# Data flow

Status: proposed, 2026-10-25. How data moves through the system in each situation. Names
match [interfaces.md](interfaces.md) and [components.md](components.md).

## 1. Ask, cloud first (phases 1 to 3)

No `Locator` yet. The user points, pinches, and the menu fills in.

```mermaid
sequenceDiagram
    autonumber
    actor U as User
    participant S as Shell (Quest)
    participant E as rev-engine
    participant R as rev-remote
    participant G as rev-gateway + router
    participant F as Gemini 3.8 Flash
    participant A as Gemini 4 Argon

    U->>S: point with hand, pinch
    S->>E: IntentEvent(Ask)
    E->>E: frame = sharpest of the latest frames
    E->>S: PointerSource.sample_at(frame.captured_at)
    E->>E: ray to pixel (camera model + DepthSource)
    E->>E: crop window around the pixel, context image, JPEG
    E->>E: device cache lookup (perceptual hash): miss
    E-->>S: ViewState: menu Asking
    E->>R: ask(AskRequest)
    R->>G: ClientMsg::Ask over WebSocket
    G->>G: auth, budget check, gateway cache lookup: miss
    G->>F: describe(Identify)
    F-->>G: Identity (box relative to crop)
    G->>G: validate, map box to frame
    G-->>R: Insight(Identity)
    R-->>E: InsightEvent::Identity
    E-->>S: ViewState: title + highlight from identity box
    G->>A: describe(Full, identity)
    loop streamed
        A-->>G: SummaryDelta, Property
        G-->>R: Insight(...)
        R-->>E: InsightEvent
        E-->>S: ViewState: menu Detailing
    end
    G->>G: assemble ObjectInsight, store in cache, record cost
    G-->>R: Insight(Done), End
    R-->>E: InsightEvent::Done
    E->>E: store in device cache
    E-->>S: ViewState: menu Complete
```

Without a `Locator` the highlight appears only once the identity arrives, and it stays
where the object was in that frame (no tracking). Good enough to measure the end-to-end
latency, which is what phases 1 to 3 are for.

## 2. Highlight loop (phase 4)

Runs continuously while the user points. Nothing here leaves the device.

```mermaid
sequenceDiagram
    autonumber
    participant C as Camera thread
    participant L as Locator thread (ort)
    participant E as rev-engine task
    participant X as XR / render thread

    loop every camera frame (30 to 60 Hz)
        C->>C: Camera2 image to Frame, replace latest
    end
    loop at locator_fps (about 15 Hz), skip if busy
        E->>L: locate(latest frame, focus near pointer)
        L->>L: YUV to RGB, resize to 320 or 640, YOLO26n
        L-->>E: detections
        E->>E: tracker: detections to tracks
        E->>E: pointer at capture time to pixel
        E->>E: focus selector with hysteresis
        E->>E: depth hit behind box center, world anchor
        E-->>X: ViewState: reticle + highlight (latest wins)
    end
    loop every display frame (72 to 120 Hz)
        X->>X: read latest ViewState, draw highlight at world anchor
    end
```

Three loops at three rates, joined only by "latest value" slots. A slow model lowers the
highlight's update rate; it never stalls the display.

## 3. Ask with a Locator (phase 4 and later)

Same as flow 1, with three differences:

1. The crop is the focused track's box plus padding, not a window around the pointer.
2. The device cache is first checked by `TrackId`: asking again about the same object while
   it is still tracked opens the menu instantly at no cost.
3. The Locator's label goes along as `hint`, and the highlight is already on screen before
   the request leaves.

## 4. Router chain and fallback

```mermaid
flowchart TD
    start(["Stage starts: identify, details or enrich"]) --> budget{"Budget left<br/>for the estimate?"}
    budget -- no --> over(["ServiceError::BudgetExceeded"])
    budget -- yes --> next["Take next provider in the chain"]
    next --> none{"Chain empty?"}
    none -- yes --> fail(["ServiceError::NoProvider<br/>with every attempt"])
    none -- no --> attempt["describe() with timeout_ms<br/>(optional hedge after hedge_after_ms)"]
    attempt --> ok{"Stream opened?"}
    ok -- "Timeout, RateLimited, Unavailable,<br/>Rejected, Unsupported" --> log1["Log attempt"] --> next
    ok -- yes --> events["Read events, validate each<br/>against the rev-prompts schema"]
    events --> bad{"Schema broken<br/>or stream error?"}
    bad -- "yes, nothing sent yet" --> log2["Log attempt"] --> next
    bad -- "yes, some events sent" --> rest["Keep what arrived;<br/>ask next provider for the rest"] --> next
    bad -- no --> done(["Stage done: record usage and cost"])
```

Every attempt (provider, latency, outcome, cost) is logged, so the scoring harness and
production logs show which providers actually carry the load.

## 5. Follow-up question (Enricher, phase 5)

```mermaid
sequenceDiagram
    autonumber
    actor U as User
    participant E as rev-engine
    participant G as rev-gateway + router
    participant N as Enricher (web search model)

    Note over E: menu is Complete, capabilities list the Price topic
    U->>E: Intent FollowUp(Price)
    E->>G: Enrich(object insight, Price, region)
    G->>G: budget check, cache lookup
    G->>N: enrich(EnrichRequest)
    loop streamed
        N-->>G: TextDelta, Fact, Source
        G-->>E: Enrichment events
        E->>E: fill FollowUpSection
    end
    G-->>E: End
```

The menu only shows follow-up buttons for topics in `ServiceCapabilities.topics`, so
clients need no update when a topic is added on the gateway.

## 6. Cancel and supersede

```mermaid
sequenceDiagram
    autonumber
    actor U as User
    participant E as rev-engine
    participant R as rev-remote
    participant G as rev-gateway
    participant P as Provider

    U->>E: Ask (object A)
    E->>R: ask(A)
    R->>G: Ask id=1
    G->>P: request for A
    U->>E: Ask (object B) or Dismiss
    E->>E: drop stream for A
    R->>G: Cancel id=1
    G->>G: drop the task for id=1
    G--xP: HTTP request aborted
    E->>R: ask(B)
    R->>G: Ask id=2
```

Only one ask is active per client. Whatever was already spent on A is still recorded.

## State machines

### Menu

```mermaid
stateDiagram-v2
    [*] --> Closed
    Closed --> Asking: Ask
    Asking --> Identified: Identity
    Asking --> Complete: device or gateway cache hit
    Identified --> Detailing: first summary or property
    Identified --> Complete: Done (OnExpand mode)
    Detailing --> Complete: Done
    Asking --> Failed: error or timeout
    Identified --> Failed: error (identity kept)
    Detailing --> Failed: error (partial text kept)
    Failed --> Asking: Retry
    Complete --> Detailing: MoreDetails (OnExpand mode)
    Asking --> Closed: Dismiss
    Identified --> Closed: Dismiss
    Detailing --> Closed: Dismiss
    Complete --> Closed: Dismiss
    Failed --> Closed: Dismiss
```

A new `Ask` from any state cancels the current request and goes to `Asking`.

### Focus (phase 4)

```mermaid
stateDiagram-v2
    [*] --> NoTarget
    NoTarget --> Candidate: pointer over a detection
    Candidate --> Focused: rested for switch_after
    Candidate --> NoTarget: pointer left
    Focused --> Candidate: pointer over another detection
    Focused --> Lost: track missing
    Lost --> Focused: track back within keep_lost_for
    Lost --> NoTarget: keep_lost_for passed
```

The highlight is drawn in `Focused` and `Lost`; `Candidate` shows only the reticle. This
keeps the highlight from flickering between neighbouring objects.

## Caching

Two levels. Both store finished `ObjectInsight`s, never images.

| Level | Where | Key | Lifetime |
| --- | --- | --- | --- |
| Device | `rev-engine` | `TrackId` (phase 4); perceptual hash of the crop, 64-bit dHash, Hamming distance at most 6 | Track: while tracked. Hash: LRU of 256 entries, cleared when the app closes |
| Gateway | `rev-router` (`moka`) | dHash of the crop, `hint` label, locale, stage, prompt version, chain id | 24 h TTL, size-capped; scoped per auth token by default |

A hash hit is accepted only if the hint labels agree (when both exist), to keep two
similar-looking objects from sharing an answer. Cache hits still log an event (with zero
cost) so hit rates are visible.

## Latency budget

Targets, to be measured in phases 1, 3 and 4.

| Stage | Highlight loop | Context menu, first line |
| --- | --- | --- |
| Camera capture | 20 to 40 ms (Meta figure) | 20 to 40 ms |
| YUV to RGB, crop, resize | under 5 ms | under 10 ms + JPEG encode (about 5 ms) |
| Model | under 40 ms on device | identify under 1.5 s, streamed |
| Network | none | 50 to 150 ms over Wi-Fi, WebSocket already open |
| **Total** | **under 100 ms** | **under 2 s to the name** |

Levers if the menu is too slow: smaller crops (fewer image tokens), `DetailsMode::Parallel`,
hedging, a faster identify model, a gateway region closer to the user.

## Threads and tasks on the Quest

```mermaid
flowchart LR
    subgraph android["Android process"]
        cam["Camera2 callback thread<br/>writes latest Frame"]
        xr["XR + render thread (Bevy)<br/>poses, hands, depth, draw"]
        subgraph tokio["tokio runtime, 2 worker threads"]
            eng["engine task"]
            net["rev-remote WebSocket task"]
        end
        inf["inference thread<br/>ort, YOLO26n"]
    end
    cam -- "latest frame slot" --> eng
    xr -- "pose history,<br/>depth, intents" --> eng
    eng -- "locate request" --> inf
    inf -- "detections" --> eng
    eng -- "ViewState (watch)" --> xr
    eng <--> net
```

The render thread never waits on anything else. It reads the latest `ViewState` and draws.
