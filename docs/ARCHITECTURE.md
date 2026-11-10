# Architecture

Sunroom is an infinite-canvas window manager for macOS. This document describes how it is put together and, more
importantly, which properties the implementation is trying to preserve. It is written for someone who is going to change
the code, not for a landing page.

Sunroom is pre-1.0. The tables at the end say what is implemented today; the rest of the document describes the design
those pieces are converging on. Where a mechanism is not built yet, it is called out rather than described in the past
tense.

## Goals and non-goals

**Goals**

- One canvas that can hold windows, notes, images and links without a hard limit on extent or count.
- Camera motion that feels direct: the point under the pointer stays under the pointer, and zoom is smooth across four
  orders of magnitude.
- A document format that is readable, diffable, and recoverable by hand.
- A Core module that can be tested without a display, a window server, or a permission prompt.
- No network, no account, no telemetry, no third-party runtime dependencies.

**Non-goals**

- Becoming a general-purpose design tool with vector editing, boolean paths, or a plugin runtime.
- Replacing the macOS window server. Sunroom mirrors and moves windows; it does not composite them.
- Cloud sync. A canvas is a file; if you want it on two Macs, put it in a folder you already sync and accept the
  conflicts.
- Sandboxing for the Mac App Store. Controlling other apps' windows through Accessibility is incompatible with the
  sandbox in the way Sunroom needs it. The trade-off is documented in [SECURITY.md](../SECURITY.md).

## Modules and the dependency rule

```
        ┌──────────────────────────────┐
        │           Sunroom            │  SwiftUI views, app lifecycle,
        │  (executable target)         │  Liquid Glass chrome, menus
        └──────────────┬───────────────┘
                       │
        ┌──────────────▼───────────────┐
        │          SunroomKit          │  ScreenCaptureKit, Accessibility,
        │  (library target)            │  AppKit bridges, command registry
        └──────────────┬───────────────┘
                       │
        ┌──────────────▼───────────────┐
        │         SunroomCore          │  geometry, documents, transforms,
        │  (library target)            │  snapping, layout, search, undo,
        └──────────────────────────────┘  persistence
```

Dependencies point one way. `SunroomCore` may import `Foundation` and `CoreGraphics`; it must never import `AppKit`,
`SwiftUI`, `ScreenCaptureKit`, `ApplicationServices`, or any AppKit-backed type. `SunroomKit` may import Core and the
platform frameworks. The app target may import both and should contain no algorithm that could live below it.

This rule is enforced twice: CI greps `Sources/SunroomCore` for forbidden imports, and review asks the question "could
this function be tested without a window server?" If the answer is yes, it belongs in Core. The payoff is concrete:
transform math, snap solving, layout, undo and migration can be covered by tests that run in seconds on a headless CI
runner, and a change to a view cannot silently change document semantics.

There is a second, softer rule: `SunroomKit` must not expose AppKit types to the app when a Core value type would do.
A window is a `WindowReference`, not an `NSWindow`. This keeps the boundary between "platform service" and "document
model" visible.

## Coordinate spaces

Four spaces matter, and confusing them is the most reliable way to introduce a bug.

| Space | Units | Origin | Axes | Where it lives |
| --- | --- | --- | --- | --- |
| **Canvas** | points | arbitrary (usually the first node) | +x right, +y down | `CanvasPoint`, `CanvasRect`; persisted |
| **View / screen** | points | top-left of the canvas viewport | +x right, +y down | `CanvasTransform`; camera state, no geometry |
| **Backing pixels** | pixels | same as view, multiplied by `backingScaleFactor` | +y down | rasterisation only |
| **AX global** | points | top-left of the primary display | +x right, +y down | `SunroomKit` only |

Canvas space is the source of truth. A node's frame is stored in canvas coordinates and is not rewritten when the camera
moves. Panning and zooming change only the transform. This is why a canvas can be edited on a 5K display, reopened on a
laptop, and it will look the same relative to its content.

View space is what the user points at. Gestures arrive in view points; convert them with `canvasPoint(fromScreen:)`
before hit-testing, snapping or dragging. Do not store a view-space value in a node "for convenience"; it will be wrong
the next time the camera moves.

Backing pixels appear only at the raster boundary. The camera is rounded to device pixels at rest
(`pixelAligned(scale:)`) so text and one-point borders stay crisp, but the rounded value is a display copy. The document
keeps the unrounded transform.

AX global coordinates are a macOS quirk worth naming. Cocoa screen coordinates have their origin at the bottom-left of
the primary display with +y up; Accessibility uses the top-left of the primary display with +y down. Displays arranged
to the left or above the primary have negative coordinates. `SunroomKit` owns the conversion in one place and never
hands an AX rect to Core as if it were a canvas rect. Window cards store the canvas frame chosen by the user; the AX
rect is an external fact, cached for placement, not part of the document's geometry.

## The camera: `CanvasTransform` invariants

The transform is the whole camera:

```
screen = canvas × zoom + translation
canvas = (screen − translation) ÷ zoom
```

`translation` is the screen-space position of the canvas origin. `zoom` is clamped to `[0.02, 12]` (2%–1200%). The
following invariants are relied on elsewhere; changing them means auditing the whole app.

1. **Zoom is always in range.** `init` and `zooming(to:anchor:)` clamp. A decoded document is also clamped by
   `migrateIfNeeded()`. There is no code path that produces a zero, negative, NaN or infinite zoom.
2. **Mapping is exact and invertible.** `canvasPoint(fromScreen: screenPoint(fromCanvas: p))` returns `p` up to floating
   point error. A round-trip test over representative points and zooms, including the extremes, is the baseline.
3. **Zoom preserves the anchor.** Given a screen anchor `a`, the canvas point under it is `c = (a − t) / z`. After
   zooming to `z'`, the new translation is `t' = a − c × z'`. `zooming(to:anchor:)` computes exactly that, which is why
   pinch and ⌘-scroll feel attached to the pointer rather than the viewport centre.
4. **Fit never exceeds 100% by default.** `fitting(_:in:padding:maxZoom:)` caps at `1.0` so fitting a small note does not
   blow it up to fill the screen. Callers that genuinely want more can pass a higher cap, but the default protects the
   common case. Empty rects or viewports fall back to centring instead of dividing by zero.
5. **Camera animation is deterministic.** `interpolate(from:to:t:)` clamps `t` to `[0, 1]`, interpolates translation
   linearly and zoom logarithmically. Log interpolation makes a 2× zoom feel like the same speed at every scale, and
   makes the result reproducible in tests. There is no spring, no frame-rate dependence and no hidden state.
6. **Pixel alignment is presentation only.** `pixelAligned(scale:)` rounds translation to `1 / scale`; it does not round
   node frames and is never encoded. Rounding geometry would accumulate drift.
7. **The transform is view state that happens to be persisted.** Each canvas remembers where you left the camera, but
   resetting the transform changes nothing about node positions. It is safe to discard.

Zoom-dependent quantities are converted deliberately: snap tolerance is divided by zoom so the pull feels constant in
screen points (`SnapConfiguration.scaled(forZoom:)`), and culling expands the visible rect by a screen-space margin
before converting it to canvas space.

## Document model

`CanvasDocument` is a value type: schema version, identity, name, `[CanvasNode]`, transform, background, grid style and
spacing, timestamps, and free-form notes. `CanvasNode` carries identity, kind, a canvas frame, title and body text,
style, optional link/image/window references, an optional parent frame, lock and collapse flags, and timestamps.

The array order is the paint order, with one exception: frames (`kind.isContainer`) are painted first so their contents
sit on top. `paintOrder` and `bringToFront` both preserve this rule. Hit-testing iterates the array in reverse so the
topmost node wins, while skipping locked nodes unless explicitly requested. A frame is a visual grouping and a parent
pointer (`groupID`), not an ownership tree: deleting a frame clears the pointer and leaves the children in place.

Node geometry is normalized on construction (`frame.standardized`), so width and height are never negative. Resizing
enforces a minimum of 60×44 points. Locked nodes are excluded from movement, resizing, alignment and distribution;
snapping targets are computed from their current frames, locked or not.

Style is stored as tokens and numbers, not colours and fonts: an accent token, optional fill/text tokens, font size,
corner radius, opacity and image content mode. A theme change or a contrast pass can restyle old documents without a
migration, and a document remains readable in a text editor.

## Spatial index

An infinite canvas can hold tens of thousands of nodes; a viewport only ever needs a handful. `SpatialIndex` is a
uniform grid over node rectangles:

- **Cell size 512 canvas points.** Typical window cards are 400–900 points wide and notes 300–500, so a node lands in one
  or two cells. Smaller cells reduce candidate work but increase bucket overhead and the number of cells a large node
  touches. 512 is the tuning point for Sunroom's content, and it is a parameter, not a law.
- **Insertion** removes any previous entry, stores the standardized rect in a dictionary, and adds the node's id to every
  cell the rect overlaps. Sets deduplicate ids across cells.
- **Query** walks the cells overlapped by the query rect, gathers candidate ids, then performs an exact
  `rect.intersects` test against the stored rect. Cells are a filter, not the answer.
- **Pathological rectangles** are capped: if a rect would span 4,096 or more cells (a frame dragged to `1e9`), it is
  filed under its minimum cell only. This keeps memory bounded; the trade-off is that an absurdly large node can be
  missed by a query far from its origin. Real frames are small compared with that guard, and a multi-level index is the
  long-term fix.
- **Rebuild** is O(n) and used when loading a document or after a bulk arrangement. Individual edits use incremental
  insert/remove.

A quadtree or R-tree would reduce worst-case query cost, but both need rebalancing and pointer chasing, and both are
harder to make deterministic. Uniform grid queries are cache-friendly, allocation-light and predictable, which matters
more for a canvas whose nodes cluster into human-sized piles.

The index is a derived structure. It is rebuilt from the document and never persisted. If the index and the document
disagree, the document wins.

## Rendering and level of detail

The renderer draws a viewport, not a document. Each frame it computes the visible canvas rect, expands it by an overscan
margin (so a fast pan does not reveal empty space), asks the index for intersecting nodes, sorts them by paint order, and
draws only those. Off-screen nodes cost an index query and nothing else.

Zoom determines how much fidelity each node gets. The thresholds live in `LevelOfDetail.forZoom(_:)`:

| Zoom | Level | What is drawn |
| --- | --- | --- |
| ≥ 62% | `full` | Live snapshots, text, controls, shadows |
| 28% – <62% | `compact` | Titles instead of body text, simplified chrome, no snapshots |
| 8% – <28% | `blocks` | Colour blocks with a label for the largest items |
| < 8% | `silhouette` | Colour rectangles only |

The intent is legibility, not just performance: four-point text is noise. Snapshots are only requested at `full`, which
is also the only level that subscribes to capture. Controls are hidden below `full` so a zoomed-out canvas does not
become a field of handles.

The thresholds are hard today. A ±5% hysteresis band is planned so a trackpad resting exactly on a boundary does not
flicker between representations. Until then, the LOD is a pure function of zoom, which makes it easy to test.

Rendering is driven by a display list and invalidated by document changes, transform changes and capture-frame updates.
The camera is applied once as a transform; node views do not each recompute the mapping. Text is rendered at the
device scale, and the camera translation is pixel-aligned at rest to keep it sharp. The app shell that implements this
renderer is in progress; the thresholds and culling rules above are the contract it is being built against.

## Undo: snapshots on purpose

Undo stores whole-document snapshots, not commands. A `CanvasDocument` is a value type of modest size, and the
operations that mutate it are pure functions. Recording the state *before* a change and restoring it later is much
easier to keep correct than maintaining an inverse for every operation, especially for operations that touch groups and
z-order.

The rules:

- `record(_:label:coalescingKey:)` is called before a mutation. The label is user-facing ("Move 3 nodes", "Rename").
- Rapid edits with the same coalescing key within 0.6 seconds collapse into one entry. A typing burst is one undo step;
  a drag is one step because the key changes when the drag ends (`endCoalescing()`).
- The stack is capped at 200 entries. Redo is cleared when a new entry is pushed. Undo pushes the current state onto the
  redo stack with the same label, so menu titles stay accurate.
- The stack is not persisted. Quitting clears history; the document on disk is the durable state.

The honest cost: snapshots duplicate the document. A 1,000-node canvas is on the order of a megabyte of Swift values, so
a long session can hold tens of megabytes of history, and a pathological canvas can hold hundreds. Typical canvases are
much smaller, coalescing removes most entries, and the cap bounds the worst case. Delta encoding or structural sharing
of unchanged nodes is the planned fix if real usage shows the memory is a problem. For now, correctness and a small
amount of code win.

## Persistence

Everything lives under `~/Library/Application Support/Sunroom`:

```
Canvases/<UUID>.json                       one document per canvas
Assets/<UUID>.<ext>                        imported images, original bytes
Backups/<UUID>-<ISO-8601>.json             previous five versions per canvas
Recovered/<name>-<epoch>.broken.json       files that failed to decode
index.json                                 reserved for a summary cache
settings.json                              local preferences
```

The current store derives sidebar summaries by scanning `Canvases/`; `index.json` is reserved for a cache once canvas
counts justify it. `StorageLocation` is injectable, so tests can use a temporary directory and never touch a real
user's library.

**Encoding.** Pretty-printed JSON with sorted keys and ISO-8601 dates. Sorted keys make diffs stable; pretty printing
makes a canvas inspectable and recoverable by hand. Assets are stored as original bytes, not base64, so a large image
does not bloat the document or every backup.

**Writes.** `Data.write(to:options:.atomic)` writes to a temporary file and renames it, so a crash mid-write leaves the
previous file intact. Before an overwrite, the existing file is copied to `Backups/` with a timestamp. Backups are
pruned to five per canvas, oldest first, using modification dates.

**Recovery.** A file that fails to decode is moved to `Recovered/` with a timestamp and a `.broken.json` suffix, and
loading continues. One corrupt canvas must never prevent the app from launching or block access to the others. The
original bytes are preserved so a human or a future migration can attempt a rescue.

**Schema and migration.** `schemaVersion` is currently `1`. Migration is additive by policy: new fields get defaults so
older documents decode; `migrateIfNeeded()` clamps grid spacing, zoom, opacity and non-standardized frames. A breaking
change increments the version and gets an explicit step. Unknown keys are dropped by `Codable`, which means a document
written by a newer build can lose fields when opened by an older one. Until that is fixed, do not open the same canvas
with a newer and an older build; refusing to save a document whose schema version is newer than the running app is
planned for 0.2.

**Import and export.** Export writes the same JSON. Import decodes, migrates, assigns a fresh document UUID and updates
the timestamp, so importing a file can never overwrite an existing canvas with a colliding id.

**Autosave.** `AutosaveController` debounces writes by 0.75 seconds on a utility queue and exposes `flush` for quit.
The app keeps the latest document value; the controller never owns mutable UI state.

## Live window cards

Window cards are how the canvas shows something that is not a note. The document model never depends on the screen:
a card stores a `WindowReference` (window number, owning PID, bundle identifier, app name, title) and the pixel frame
lives in an in-memory cache.

**Discovery.** `WindowDiscovery` asks `CGWindowListCopyWindowInfo` for layer-0 windows, filters out tiny windows
(badges, tooltips), zero-alpha windows, the Dock, the menu bar and Sunroom itself, and converts frames from the window
server's top-left coordinate space into AppKit's bottom-left space. The result is refreshed on a four-second timer and
on demand.

**Capture.** `WindowCaptureService` uses `SCShareableContent` to resolve a `CGWindowID` to an `SCWindow`, then
`SCScreenshotManager.captureImage` with an `SCContentFilter(desktopIndependentWindow:)`. It captures a still frame at a
capped pixel size rather than opening a `SCStream`: a canvas can show dozens of cards, cards change slowly, and a
per-window video stream per card is exactly the kind of battery cost a desktop app should not have. Frames are
requested at most once per `refreshInterval` (default 1 s) per window, with two captures in flight at a time, and are
delivered to the main actor as immutable `NSImage` values.

**Throttle.** A snapshot is only requested for a window whose card is visible and at full level of detail. Snapshot
requests are coalesced per window, so panning and hovering cannot queue work. Capture is disabled entirely when the
user turns previews off in Settings; cards keep their last frame and are drawn with a placeholder instead of a stale
mirror when no frame has ever arrived.

**What it cannot do.** Protected video may capture black. Minimised windows have no frames. Some apps redraw in ways
that look like flicker at 1 fps. Full-screen apps in another Space may not be shareable. The card is a mirror, not a
remote desktop.

## Accessibility and window control

Moving other apps' windows is the least reliable part of macOS window management. Sunroom treats it as an external,
fallible service.

**Permission.** `AXIsProcessTrusted()` is the check; `AXIsProcessTrustedWithOptions` with the prompt option is the
request. Both permissions are optional: without Accessibility the canvas is still a notes-and-images surface. The
permission state is refreshed when the app becomes active, so returning from System Settings updates the UI without a
relaunch.

**Window matching.** macOS has no public `CGWindowID` → `AXUIElement` mapping. Sunroom resolves
`_AXUIElementGetWindow` with `dlsym` at runtime — the same private-but-stable symbol yabai, AeroSpace and Rectangle
use — and falls back to accepting a match only when the app exposes exactly one window. If several windows are open and
the symbol is missing, it refuses rather than risking the wrong window. This is the one private API in the project and
it is isolated to `AccessibilityWindowController.axWindow(for:pid:)`.

**Writes.** `setFrame` applies size before position (macOS clamps positions to keep windows on screen, so growing first
avoids a visible jump), and returns whether each attribute was accepted. Long operations — a layout push, an animated
move — run on a dedicated serial queue, never the main thread, and report completion back on the main actor. A failed
write degrades to "cannot move this window" and surfaces a toast; it never retries forever.

**Choreography, not a compositor.** Public macOS APIs cannot composite another app's window into your own view, so
Sunroom cannot be a compositor-level plane like phantomat on Hyprland. The canvas is the planner and the desktop is the
output: **Capture desktop** builds cards that mirror the current window layout, and **Apply layout to desktop** moves
the real windows into the cards' positions with an eased tween. Windows keep their own rendering, input and frame rate
throughout.

**Scope.** Sunroom touches only windows the user explicitly put on a canvas. It does not enumerate-and-tile everything
it can see, does not send keystrokes, does not press buttons, and does not read window text content beyond the title
needed to label a card.

## Concurrency

- **Main actor:** document state, selection, camera and all view updates. Mutations are synchronous and cheap; the
  document is a value type, so an edit is a copy-on-write update.
- **Core:** types are `Sendable` values. No Core API starts a task or owns a queue.
- **Persistence:** encoding and disk writes on a utility queue; the result is reported back to the main actor. A failed
  write is surfaced, not retried forever.
- **Capture:** ScreenCaptureKit owns its queues; frames are delivered as immutable images and applied on the main actor.
- **Accessibility:** a dedicated serial queue, with per-PID ordering. No AX call is made while holding a lock that the
  main thread might need.

The rule of thumb: the main thread may wait for a value, but never for the window server, the disk, or another app.

## Testing strategy

Core tests are deterministic and headless — 285 assertions across twelve files, run in under a second. Every Core
change is expected to bring its own:

- Transform round-trips at the zoom extremes and at non-integer anchors.
- Fit and centre behaviour for empty, tiny and huge rects and viewports.
- Spatial index queries checked against a brute-force scan, including nodes spanning cell boundaries.
- Snap solving for edge, centre, grid, multi-selection and disabled configurations.
- Layout ordering and the "map back to input order" behaviour of `reflow`.
- Undo coalescing, redo clearing and the entry cap.
- Persistence: atomic save, backup pruning, quarantine, import identity, and migration from older fixtures.
- JSON round-trip equality for a document with every node kind.

Tests that need a window, a permission or a display are not in CI. They are verified manually with a screenshot and a
note in the pull request, because a test that can only run on the author's Mac is a story, not a test. Visual review
uses `SunroomRender`, a headless executable that draws canvases to PNG using the same renderer as the app, so a
regression in the canvas look shows up as a changed image rather than a subtle complaint.

## Invariants worth protecting

If a change violates one of these, stop and reconsider the change:

1. Core imports only Foundation and CoreGraphics.
2. Canvas geometry is the only persisted geometry; screen coordinates never enter a document.
3. `zoom` is clamped and mapping is invertible.
4. Node frames are standardized with non-negative size.
5. Frames paint behind their contents; array order otherwise wins.
6. `groupID` points to an existing frame or is `nil`.
7. A document round-trips through JSON without semantic change.
8. Capture frames are never written to disk.
9. Long AX operations never run on the main thread.
10. A corrupt file is preserved, not deleted.

## Status

| Area | State | Lives in |
| --- | --- | --- |
| Geometry, transform, spatial index | Implemented | `SunroomCore` |
| Document model, editing operations | Implemented | `SunroomCore` |
| Snapping, layouts, minimap projection | Implemented | `SunroomCore` |
| Snapshot undo, persistence, migration | Implemented | `SunroomCore` |
| Fuzzy search | Implemented | `SunroomCore` |
| Window reference model | Implemented (schema only) | `SunroomCore` |
| ScreenCaptureKit card pipeline | In progress | `SunroomKit` |
| Accessibility placement and layout push | In progress | `SunroomKit` |
| Command registry, palette | In progress | `SunroomKit` |
| SwiftUI app shell and Liquid Glass chrome | In progress | `Sunroom` |

The design in this document is the contract. The status table is the truth about today.
