# Roadmap

This is a working document, not a promise. It says what is being built, in what order, and why. Dates are deliberately
absent: Sunroom is a small project, and a missed date is worse than no date. When something ships, it moves from here
into [CHANGELOG.md](../CHANGELOG.md), and the line is deleted rather than left as a trophy.

## How to read this

- **Now** is the current development cycle and the only part with committed scope.
- **Next** is agreed direction, not scheduled work.
- **Later** is a direction of travel that may change with what real use teaches us.
- **Not planned** is as useful as the rest. It keeps the product from drifting.

The ordering principle is simple: make the core loop trustworthy before making it broader. The core loop is *put a
window on a plane, arrange it, and have the arrangement stick*. Everything else is secondary until that feels
effortless.

## Now — 0.2, window cards and placement

The document model and canvas engine are in place. The work is connecting them to the window server without making the
app fragile.

**Capture**

- ScreenCaptureKit discovery, filtering and the window picker.
- A bounded stream pool for visible cards at full level of detail, two frames per second, capped resolution.
- Stale-frame states: occluded, minimized, paused, permission denied, protected content.
- Pause on inactivity, occlusion, Low Power Mode, display sleep and an explicit shortcut.
- Memory budget and eviction; no captures written to disk.

**Placement**

- Accessibility permission onboarding with a clear explanation and a relaunch path.
- Matching a `WindowReference` to an AX window using public attributes, with honest failure instead of a wrong move.
- Batched position and size writes on a serial queue, coalesced during drags, verified by read-back.
- "Push layout": apply the canvas arrangement to the real windows, with a confirmation and a report of what refused.
- Multi-display coordinates, including negative-origin displays and mixed scale factors.

**App shell**

- The real SwiftUI window: canvas, sidebar, inspector, Liquid Glass toolbar, menu bar.
- Command registry and ⌘K palette, with availability and disabled reasons.
- Onboarding that asks for nothing until a feature needs it.
- Crash-safe autosave wiring and a visible save state.

**Release engineering**

- Ad-hoc signing in the local build, Developer ID signing and notarisation for tagged releases once a certificate is
  available. Until then, release notes say plainly that the build is unsigned.
- A UI smoke test and an accessibility pass on the canvas container.
- Test coverage for the capture and AX state machines using protocol seams and fakes, so CI does not need a real screen.

**Exit criteria:** place five windows, arrange them, push the layout, relaunch, and have the same canvas with reliable
cards. No permission prompt until a window feature is used. Capture stops when the app is hidden.

## Next — 0.3, multi-display and daily use

- **Display regions.** Map a canvas region to a physical display so "fit this board to the Studio Display" is one
  command. Display-aware fit and a sane behaviour when a display disconnects.
- **Spaces and Stage Manager.** Detect full-screen windows and managed spaces, and refuse to fight the system. Document
  what cannot be controlled rather than failing mysteriously.
- **Layout profiles.** Save the arrangement of a set of windows and restore it later. Per-canvas, not per-app magic.
- **Custom shortcuts.** The command registry's stable ids become the storage key; the reference table is generated from
  the registry.
- **Export.** PNG and PDF of a selection or the whole board, at a chosen scale, with a background or transparent.
- **Performance budget.** 25,000 nodes at 60 fps during pan on an M1 MacBook Air, with a regression test that measures
  index query and render-list construction rather than wall-clock frames.
- **Undo memory.** Delta encoding or structural sharing for snapshots, so a long session on a large canvas does not
  cost hundreds of megabytes.

## Later — 0.4 and beyond

These are directions, not commitments.

- **Presentation mode.** A read-only, full-screen view of a board for a review or a demo. No editing chrome, no window
  capture unless explicitly enabled.
- **Board linking.** A card that points at another canvas, with a breadcrumb. Useful for projects that outgrow one
  plane; dangerous as a way to recreate folders, so it ships only if the interaction stays flat.
- **Spatial search.** Search results placed temporarily on the plane relative to the current view, instead of in a
  list. The list remains for accessibility.
- **Local text recognition in images.** Vision-based OCR, on device, opt-in per image. No network, no index upload.
- **Window sets.** A named collection of app windows that can be placed as a group, for recurring meetings or reviews.
- **A small extension surface.** Possibly URL schemes or Shortcuts actions; not a plugin runtime. Any extension points
  must preserve the local-first, no-network model.
- **File-based collaboration.** If two people want to share a board, the honest version is a folder both already sync
  and a conflict model that preserves both files. No server, no accounts.

## Not planned

- **Accounts, a hosted sync service, or a subscription.** Sunroom is a local tool. A canvas is a file you own.
- **Telemetry, analytics or "anonymous usage data".** The absence is a feature, and it is in the security policy.
- **A sandboxed Mac App Store build.** The Accessibility control Sunroom needs is not compatible with the sandbox in
  the way the product requires. A separate, reduced canvas-only build is conceivable; it is not on the roadmap.
- **A mobile or web client.** The product is about controlling macOS windows. A viewer without the window server is a
  different product.
- **AI summaries, automatic tagging or a chatbot over your notes.** Local models are interesting; bolting a chat box
  onto a canvas is not. If this ever happens it will be an explicit, local, opt-in tool, not a default surface.
- **Replacing the macOS window manager.** Sunroom arranges windows you choose. It does not tile every window
  automatically, manage spaces for you, or hide the system UI.

## Known debt

Honest accounting of things that are not done and are not hidden:

- `index.json` is reserved but unused; sidebar summaries currently scan every canvas file. Fine at tens of canvases,
  not at thousands.
- A document with a newer `schemaVersion` is decoded and can lose unknown fields when saved. Refusing to save a
  too-new document is planned for 0.2.
- Level-of-detail thresholds have no hysteresis, so a zoom parked exactly on a boundary can flicker.
- Undo snapshots duplicate the whole document; memory grows with canvas size and history length.
- The Accessibility window match is best-effort without private SPI. A renamed window may need a re-match.
- The spatial index files pathological rectangles under a single cell, which can make a query miss a node of absurd
  size. Real frames are nowhere near that size; a multi-level index is the long-term fix.
- The Core test suite is a smoke test today. Transform round-trips, snapping, layout, undo, migration and spatial-index
  behaviour still need the tests described in [ARCHITECTURE.md](ARCHITECTURE.md). Expanding them is part of 0.2.
- The UI is not yet audited with VoiceOver end to end. The requirements exist in
  [CONTRIBUTING.md](../CONTRIBUTING.md); the audit is part of 0.2.

## How priorities are chosen

1. Does it protect a user's work? Persistence, undo and recovery outrank every feature.
2. Does it make the core loop more reliable? Capture and placement before new node types.
3. Does it remove a papercut people hit weekly? Keyboard conflicts and permission clarity are high-value.
4. Does it fit the model? A feature that needs a server, an account or a second source of truth is not a fit, however
   nice the demo.

## How to influence it

Open an issue with the problem, not only the proposed feature. "I have four windows for a review and I lose their
arrangement every Monday" is more useful than "add layout profiles", because it tells us where the friction actually
is. Reproductions, screenshots of a board that does not work, and performance traces on a large canvas are the most
persuasive inputs. See [CONTRIBUTING.md](../CONTRIBUTING.md) for how to send them.
