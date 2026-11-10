# Quality log

What has been verified, how, and what is still unverified. Updated with each release.

## Automated

| Area | Coverage | Command |
| --- | --- | --- |
| Camera, geometry, spatial index, snapping | 93 tests | `swift test` |
| Document operations, undo, persistence, migration | 115 tests | `swift test` |
| Layout, level of detail, minimap, search | 48 tests | `swift test` |
| Sample canvas, performance budgets | 19 tests | `swift test` |
| Kit: desktop mapping, coordinate conversion, settings, store | 21 tests | `swift test` |
| Desktop plane: fitting, camera, layout, tiling, navigation | 23 tests | `swift test` |
| **Total** | **324 tests, headless, ~1 s** | |

The Core suite is platform-free, so it runs on any Mac and in CI without a window
server, a display or a TCC prompt.

## Visual

`SunroomRender` draws canvases to PNG with the production renderer:

```sh
swift run SunroomRender --out /tmp/sunroom-shots
```

The app can screenshot itself, including chrome, which is how `docs/images` is
produced:

```sh
./Scripts/build-app.sh
./dist/Sunroom.app/Contents/MacOS/Sunroom --snapshot /tmp/ui --quit-after-snapshot
```

Self-capture uses `CGWindowListCreateImage` on the app's own window, so it needs
no Screen Recording permission and is deterministic.

Reviewed this release: light and dark canvas, command palette, inspector,
onboarding, window library, search state, inline editing, five backgrounds.

## Manual checks performed (2026-11-10, macOS 26.3, arm64)

- Cold launch with no `~/Library/Application Support/Sunroom` → onboarding, then
  the welcome canvas at a sensible zoom.
- Launch with an existing store → last canvas restored, no onboarding.
- Universal bundle (`arm64` + `x86_64`) launches and renders.
- Window library lists 15 real windows with app icons and no Sunroom/Dock/menu-bar
  entries.
- Accessibility not granted → the permission card appears in the sidebar and the
  canvas remains fully usable.
- Screen Recording not granted → no prompt at launch; previews are requested only
  from the permission UI.
- Snapshot mode is idempotent and quits cleanly.
- `swift build -c release`, `swift test`, `make app`, `make release` all succeed.

## Canvas mode (0.2)

Verified by tests and by construction, **not yet by eye on this machine**:

- Plane fitting, camera solving, normalise/park/stack, directional navigation and tile geometry are unit tested.
- The AX arrival path compiles against real window elements, but no Accessibility grant was available in the build
  environment, so the first live run is the user's.
- Window-restore is best-effort by design: frames captured at entry are re-applied on exit; a window that closed is
  skipped.
- The overlay uses `screenSaver` level and the surface `desktopWindow + 1`; both are standard public window levels.

What to check on a granted machine: `⌃⌥Space` gathers only the current display; pinch keeps the point under the cursor
still; clicking goes in and back; dragging to an edge tiles; `Esc` restores every window to its starting frame.

## Not verified yet

- Behaviour on macOS 14/15 with the material fallback (only macOS 26 hardware was
  available).
- Intel performance with a 5,000-node canvas.
- Animated Accessibility layout pushes against every app (tested against Finder,
  Safari and a few Electron apps).
- Notarised distribution: builds are ad-hoc signed.
- Multi-display layout mapping is implemented but only exercised on one display.

## Known limitations

- macOS offers no public API to composite another app's window into a view, so
  the canvas plans layouts and `Apply Layout to Desktop` moves the real windows;
  it is not a live compositor plane.
- Window matching uses `_AXUIElementGetWindow` (private but stable). If it is
  ever removed, apps with more than one window cannot be matched and Sunroom
  refuses rather than guessing.
- Protected video may capture black; minimised windows have no frames.
- Documents from a future schema are read tolerantly but unknown fields are
  dropped on save.

## CI note

`.github/workflows/ci.yml` builds, tests, enforces Core's import rule and packages
the app on `macos-15`. At the time of the 0.1.0 release the repository owner's
GitHub account had Actions locked for a billing reason, so the workflow could not
execute. Everything it runs passes locally; the badge stays off until Actions is
available.
