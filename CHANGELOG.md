# Changelog

All notable changes to Sunroom are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). While the version is below 1.0, minor releases may include
breaking changes to the document schema; those changes always ship with a migration.

## [0.2.0] - 2026-11-10

Canvas mode: the desktop as one plane of live windows.

### Added

- **Canvas mode.** `⌃⌥Space` gathers the windows on the current display, keeps their arrangement and zooms out until
  everything fits. Two-finger pan, pinch zoom, double-tap to fit.
- **Click to go in.** A window animates to fill the screen and its app comes forward; `⌃⌥Space` returns to the plane.
- **Drag to arrange.** Move windows on the plane, drop one on another to stack it, or on a screen edge to tile to that
  half or quarter, with a live preview of the target.
- **Keyboard navigation.** Arrows select the nearest window, `↩` goes in, `Tab` cycles, `F` fits, `Esc` restores the
  desktop exactly as it was.
- **Per-display planes.** Only the display you invoke canvas mode on is gathered; other screens are untouched.
  Window positions are remembered per app and title in `plane-layout.json`.
- **A separate plane engine in Core.** Fitting zoom, camera solving, normalise/park/stack layout, directional
  navigation and tile geometry, with 23 new tests.
- **Overlay windows.** A desktop-level surface for the canvas and a screen-saver-level transparent overlay that owns
  the pointer while canvas mode is on.

### Changed

- The README now leads with canvas mode and describes boards as the secondary surface.
- The global `⌥Space` hot key now summons the boards window; `⌃⌥Space` is canvas mode.

### Notes

- macOS refuses compositor transforms for windows an app does not own (`CGSSetWindowTransform` returns success but
  silently no-ops; the check is server-side and keyed to the mach port). Canvas mode therefore moves and resizes real
  windows through Accessibility: content reflows at zoom, and zoom clamps at roughly one third because apps enforce
  minimum sizes. This is documented in the README and the architecture notes.

## [Unreleased]

### Added

- Architecture, keyboard reference and roadmap documents.
- Security policy, contribution guide, code of conduct and issue/PR templates.
- CI for release builds and tests, plus a tagged release workflow that publishes a universal app and `SHA256SUMS`.
- `Makefile` targets for building, testing, packaging, running and cleaning.
- SwiftLint configuration tuned for a SwiftUI/AppKit codebase.

### Changed

- README rewritten around the canvas-first workspace model, with design mockups and a build-from-source guide.

## [0.1.0] - 2026-11-10

The first public release. The infinite canvas, live window cards, Accessibility-driven window arrangement, Liquid
Glass interface and the full keyboard model all ship together.

### Added

- **Live window cards.** Any window becomes a card on the plane, captured with `SCScreenshotManager` at a capped pixel
  size and refreshed at most once per second, two captures in flight.
- **Desktop capture and layout push.** Turn the current desktop into cards laid out like your screens, rearrange them
  on the canvas, then move the real windows into those positions with an eased Accessibility tween.
- **Window actions.** Focus, move-to-card, centre, full screen, minimise, close and refresh, from the card's context
  menu or the inspector.
- **Liquid Glass interface.** Floating glass sidebar, toolbar, inspector and minimap, with a material fallback on
  macOS 14 and 15; five canvas backgrounds and a dot/line grid that keeps its density as you zoom.
- **⌘K command palette** with 47 wired commands, fuzzy ranking, arrow-key navigation and ⌘1–⌘9 shortcuts.
- **Onboarding** that explains the plane, asks for the two optional permissions in context, and never blocks the canvas.
- **Settings** for appearance, accent, grid, snapping, capture cadence, launch at login and the global summon hot key.
- **Snapshot mode** (`--snapshot <dir>`) and a headless `SunroomRender` executable used for documentation and visual
  review.
- **Infinite canvas document model.** Unbounded canvas space, stable node identity, creation and update timestamps, and
  a versioned `CanvasDocument` that encodes to readable JSON.
- **Node types** for notes, text cards, images, links, frames, shapes, and live window cards. Frames paint behind their
  contents; window cards store a stable reference to a real macOS window.
- **Camera transform** with the `screen = canvas × zoom + translation` mapping, anchor-preserving zoom, fit-all and
  fit-selection, centring, pixel alignment, and log-space interpolation for camera animations.
- **Uniform spatial index** with 512-point cells for viewport culling and hit-testing, including a guard against
  pathological rectangles.
- **Level-of-detail thresholds** — full, compact, blocks and silhouette — so far-out views stay cheap and legible.
- **Snapping** to edges, centres and an optional grid, solved independently per axis, with visible guide lines.
- **Layout engine** with grid, rows, columns and radial arrangements, plus a best-arrangement heuristic based on the
  golden ratio.
- **Frames and grouping.** Group a selection into a frame, adopt contained nodes, ungroup without moving anything, and
  re-parent orphans when a frame is deleted.
- **Editing operations.** Move, resize, nudge, duplicate, lock, collapse, align, distribute, and four z-order commands.
  All are pure value-type operations on the document.
- **Snapshot undo and redo** with a 200-entry limit and a 0.6-second coalescing window, so typing and dragging collapse
  into sensible steps.
- **Local persistence.** Pretty-printed, sorted-key JSON; atomic writes; five rotating backups per canvas; corrupt files
  quarantined to `Recovered/` instead of deleted; JSON import with a fresh document identity.
- **Debounced autosave** (0.75 s) with an explicit flush on quit.
- **Fuzzy search** over note titles, body text, link hosts and window titles, using a dependency-free matcher that
  favours prefixes, word starts and camel-case boundaries.
- **Minimap projection** that unions content and viewport bounds so the indicator never leaves the map.
- **Colour tokens** stored by name rather than hex, so themes and accessibility passes do not require a document
  migration.
- **Sample canvas** for first launch and previews.
- **301 headless tests** across geometry, transform, spatial index, snapping, document operations, undo, persistence,
  layout, search and the sample canvas.
- **MIT licence.**

### Security

- No network code, no telemetry, no accounts and no third-party dependencies.

[Unreleased]: https://github.com/shashvat1965/sunroom/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/shashvat1965/sunroom/releases/tag/v0.1.0
