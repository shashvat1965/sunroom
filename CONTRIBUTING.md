# Contributing to Sunroom

Thanks for taking the time to look. Sunroom is a small, local-first macOS app, and the best contributions are usually
small too: a clear bug report, a failing test with a fix, a sentence of documentation that was wrong.

This guide covers the development loop, the rules that keep the codebase honest, and the two extension points people
ask about most: adding a node type and adding a command.

By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md). For security issues, follow
[SECURITY.md](SECURITY.md) instead of opening a public issue.

## Requirements

- macOS 14 Sonoma or later
- Xcode 16 or later (Swift 6 toolchain), with the macOS SDK
- `make` and the standard command-line tools
- Optional: [SwiftLint](https://github.com/realm/SwiftLint) if you want local style feedback. CI does not require it.

There are no third-party Swift packages, and adding one is a design decision, not a convenience. The app should build
with a clean checkout and a stock Xcode.

## Get set up

```sh
git clone https://github.com/shashvat1965/sunroom.git
cd sunroom
swift build
swift test
```

To build the app bundle and run it:

```sh
make app
make run
```

`make app` invokes `Scripts/build-app.sh`, which defaults to a release build of the current architecture, writes
`dist/Sunroom.app`, ad-hoc signs it and prints the path. `make release` adds `--universal` and produces a universal
build and a zip in `dist/`. To build with Xcode, open `Package.swift`; there is no separate project file to keep in
sync.

Useful during development:

```sh
swift test --filter SmokeTests              # one suite
swift build -c release                      # what CI builds
swiftlint                                   # optional, reads .swiftlint.yml
```

## Repository layout

```
Sources/SunroomCore/   model and algorithms. Foundation + CoreGraphics only.
Sources/SunroomKit/    ScreenCaptureKit, Accessibility, AppKit bridges, commands.
Sources/Sunroom/       SwiftUI views and app lifecycle.
Tests/SunroomCoreTests/
docs/                  architecture, keyboard reference, roadmap
Scripts/               packaging and icon generation
```

The dependency rule is one-way: `Sunroom → SunroomKit → SunroomCore`. Core must never import AppKit, SwiftUI,
ScreenCaptureKit or ApplicationServices, and CI greps for that. If a view needs a calculation, the calculation belongs
in Core, where it can be tested without a window server.

## Code style

- **Swift 6, with restraint.** The package uses the Swift 6 tools with language mode 5 per target while the codebase
  finishes its concurrency migration. New code should be `Sendable`-clean, avoid new warnings, and prefer structured
  concurrency over callbacks.
- **No third-party dependencies.** If you need something small, write it and test it. A dependency needs a strong,
  discussed reason.
- **Value types first.** Documents and nodes are `struct`s. Reference types are for controllers, caches and platform
  objects that genuinely have identity.
- **Keep Core pure.** Foundation and CoreGraphics only. No `import AppKit`, no `NSColor`, no `NSWorkspace`.
- **Names say what things are.** `CanvasTransform`, not `ViewState`. `snap(bounds:targets:)`, not `doSnap`.
- **Comments explain why.** The code already says what it does. A comment should record a constraint, a macOS quirk,
  or a decision that would otherwise be re-litigated.
- **Line length 140.** SwiftLint warns at 140 and errors at 200; see `.swiftlint.yml`.
- **Avoid force unwraps** outside tests and genuinely impossible cases. Prefer early returns and `guard`.
- **Errors are values or typed throws.** Do not swallow a failure that the user can act on. Persistence errors are
  surfaced, not logged and forgotten.
- **No emoji in source or UI strings.** The canvas is calm; keep the code calm too.

Run `swift build && swift test` before opening a pull request. If you touch persistence, also run the app once, quit,
and confirm the JSON on disk is still readable.

## Tests

Tests live in `Tests/SunroomCoreTests/` and use XCTest. Good tests for this project have three properties:

1. They are deterministic. No dates, no random UUIDs, no window server, no sleep.
2. They test behaviour at the seam: transform math, snap solving, layout ordering, undo coalescing, migration, round
   trips through JSON.
3. They include the awkward case. A rect dragged to a huge coordinate. A zero-sized viewport. A document saved by a
   future version. A selection with one locked node.

UI behaviour that needs AppKit is verified manually and with a screenshot in the pull request. Do not add a test that
requires Accessibility or Screen Recording permission to run in CI.

## Commit conventions

Use [Conventional Commits](https://www.conventionalcommits.org/), with a scope when it helps:

```
feat(core): snap selection bounds instead of individual nodes
fix(kit): avoid AX writes while a window is full-screen
docs: correct the fit-selection shortcut
test(core): cover zero-size viewport in fitting()
build: bump the deployment target to macOS 14
chore: remove an unused import
```

- One logical change per commit. Formatting-only commits should be separate and labelled `style:`.
- The subject is imperative, lower-case after the type, and under 72 characters.
- Explain the user-visible effect in the body if it is not obvious.
- Reference issues with `Refs #123` or `Fixes #123`. Do not put issue numbers in the subject.
- Do not commit generated files: `.build/`, `dist/`, `*.app`, `Resources/AppIcon.icns`.

## Pull requests

A pull request is ready when:

- CI is green: release build, tests, and the Core-import check.
- The change is focused. Unrelated refactors belong in another pull request.
- New behaviour has a test, or a short explanation of why it cannot have one.
- User-facing changes update `CHANGELOG.md` under **Unreleased**.
- Keyboard changes update `docs/KEYBOARD.md`, and the README table if it is a headline shortcut.
- UI changes include a before/after screenshot or a short screen recording.
- Persistence changes include the migration story and a test that loads an old document.
- Accessibility was considered, not bolted on: labels, focus order, Reduce Motion, Increase Contrast.

Keep the description short: what changed, why, how you tested it, and anything you are unsure about. Draft pull
requests are welcome early if you want direction before polishing.

## Adding a node type

Node types are a closed enum today, deliberately: every place that switches on `NodeKind` must be updated, and the
compiler helps. The steps:

1. **Model.** Add a case to `NodeKind` in `Sources/SunroomCore/Models.swift`, plus `displayName`, `symbolName` and the
   appropriate capability flags (`isContainer`, `isTextual`, `isSnapshotable`).
2. **Storage.** Add any new fields to `CanvasNode` with defaults so old documents decode. If the field changes meaning
   rather than adding one, bump `CanvasDocument.currentSchemaVersion` and write a migration step in
   `migrateIfNeeded()`.
3. **Operations.** Add creation and editing primitives to `DocumentOperations.swift` as pure mutating methods. Keep
   them undo-agnostic; the app records a snapshot before calling them.
4. **Seed data.** If the type benefits from a demo, extend `SampleCanvas.swift`. Do not make the demo depend on the
   user's real windows.
5. **Rendering.** Add the view in the app target and a case in the canvas renderer's node switch. Respect level of
   detail: the type needs a compact and a silhouette representation, even if that is only a coloured block.
6. **Search and accessibility.** Include the type's searchable text in `CanvasNode.searchableText`, and give it an
   accessibility label, value and hint. A node that VoiceOver cannot describe is not finished.
7. **Commands.** Add a creation command and a palette entry so the type is reachable without the mouse.
8. **Tests.** Cover insertion, duplication, removal, JSON round trip, and migration from a document that predates the
   field.

If the type needs a new system permission, stop and open an issue first. Permissions are the most expensive thing a
local-first app can ask for.

## Adding a command

The command surface is intentionally one list. When it lands with the 0.2 app shell, a command in
`Sources/SunroomKit/Commands/` will carry:

- a stable string `id` (used by the palette, menus and future custom bindings),
- a title and an optional subtitle,
- an optional keyboard shortcut,
- an availability check (selection required, window card selected, capture paused, and so on),
- a `run` closure that calls into Core or the appropriate service.

To add one:

1. Define the command next to the existing commands for its area.
2. Add it to the registry so the palette picks it up. Do not create a second path through a menu item; the menu item
   should invoke the same command value.
3. Give it a shortcut only if it is used often enough to deserve one, and check it against the system and the full
   table in `docs/KEYBOARD.md`. A conflict is a bug.
4. Make availability honest: a command that cannot run should be disabled with a reason, not silently fail.
5. Test the underlying operation in Core. Commands themselves are thin enough that a UI test is usually overkill.
6. Update `docs/KEYBOARD.md` if you added a binding, and `CHANGELOG.md` if the command is user-facing.

Shortcuts are not user-customisable yet. Keeping the registry as the single source of truth is what will make that
possible later without a second refactor.

## Accessibility requirements

Sunroom is a spatial app, which makes accessibility both harder and more important. A pull request that adds UI is
expected to meet these:

- **Every node has a label, a value and a hint.** The label is the node's title or a sensible fallback; the value
  carries the text or window title; the hint says what activation does.
- **The canvas is a container with ordered children.** VoiceOver should encounter nodes in visual order (top-to-bottom,
  left-to-right), not in dictionary or insertion order. Selection state is exposed, not implied by colour.
- **Everything reachable by mouse is reachable by keyboard.** Hover-only affordances need a keyboard route and a focus
  state.
- **Respect Reduce Motion.** Camera animations become cuts when the setting is on. No parallax, no spring overshoot.
- **Respect Increase Contrast and Reduce Transparency.** Liquid Glass falls back to an opaque surface with a defined
  border. Never rely on translucency to separate two surfaces.
- **Do not encode meaning in colour alone.** Locked, selected, stale and errored states each need a shape or text cue.
- **Hit targets are at least 28×28 points at 100% zoom**, and controls scale with the interface, not with canvas zoom.
- **Test with VoiceOver once.** Turn it on, navigate a canvas with three node types, select and move one. If you cannot
  finish, neither can someone else.

Mention the accessibility work in the pull request, even when it is just "labels added, Reduce Motion respected".

## Documentation and changelog

- User-facing behaviour goes in `CHANGELOG.md` under **Unreleased**, in the Keep a Changelog categories.
- Architectural decisions go in `docs/ARCHITECTURE.md` only if they change an invariant, a threshold or a format.
- Shortcut changes go in `docs/KEYBOARD.md`.
- Roadmap items move only when they actually ship. Optimism belongs in the issue tracker, not the roadmap.

## Questions

Open a discussion or an issue with the `question` label. If you are unsure whether a change fits, ask before writing a
large patch; a short design note in an issue is cheaper for everyone than a rejected pull request.
