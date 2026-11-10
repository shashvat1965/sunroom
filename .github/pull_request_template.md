# Pull request

## Summary

<!-- What changed, in two or three sentences. Link the user-visible effect. -->

## Related issue

<!-- Fixes #123, Refs #456, or "none". -->

## Type of change

- [ ] Bug fix
- [ ] New feature
- [ ] Document model or persistence change
- [ ] Performance improvement
- [ ] Refactor with no behaviour change
- [ ] Documentation, build or CI

## How this was tested

- [ ] `swift build -c release`
- [ ] `swift test`
- [ ] `make app` and launched the result
- [ ] Manually exercised the changed interaction

<!-- Describe the test cases. If a behaviour cannot be tested automatically, say why and describe the manual check. -->

## Screenshots

<!-- For UI changes: before/after or a short recording. Remove private canvas content. -->

## Checklist

- [ ] The change is focused; unrelated refactors are in a separate pull request.
- [ ] `SunroomCore` still imports only Foundation/CoreGraphics (no AppKit, SwiftUI, ScreenCaptureKit or ApplicationServices).
- [ ] New behaviour has a test, or the PR explains why it cannot have one.
- [ ] User-facing changes are listed in `CHANGELOG.md` under **Unreleased**.
- [ ] Keyboard changes update `docs/KEYBOARD.md` (and the README table for headline shortcuts).
- [ ] Persistence changes include a migration story and a test that loads an older document.
- [ ] Accessibility considered: labels, focus order, Reduce Motion, Increase Contrast, hit targets.
- [ ] No new third-party dependencies.
- [ ] No private data, secrets or generated build output is included.

## Notes for reviewers

<!-- Anything you are unsure about, trade-offs made, or follow-up work deliberately left out. -->
