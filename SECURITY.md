# Security Policy

Sunroom is a local-first macOS app. It has no accounts, no server, no telemetry and no network code. That removes a
large class of risk, but it does not remove all of it: Sunroom asks for powerful macOS permissions and it stores the
things you put on your canvas. This document explains the threat model, what is stored and where, and how to report a
problem.

## Supported versions

| Version | Supported |
| --- | --- |
| 0.1.x (current) | Yes, best effort |
| Pre-release builds from `main` | No — rebuild from the latest `main` |

Sunroom is pre-1.0. Security fixes land on `main` first and are included in the next tagged release.

## Reporting a vulnerability

Please **do not open a public issue** for a security problem.

Use GitHub's private vulnerability reporting:

1. Go to <https://github.com/shashvat1965/sunroom/security/advisories/new>.
2. Describe the issue, the affected version or commit, and the impact.
3. Include reproduction steps and, if possible, a minimal proof of concept.

If GitHub's private reporting is unavailable, email **security@sunroom.app** with the same information. That address is
a placeholder until public launch; if it does not reach a human, open a normal issue that says only "I need a private
security contact" and wait for a reply before sharing details.

What to expect:

- An acknowledgement within 3 working days.
- An initial assessment within 7 working days, including whether the report is in scope.
- A fix or a mitigation plan within 90 days for confirmed issues, coordinated with you on disclosure timing.
- Credit in the release notes if you want it. There is no bug bounty.

Please give us a reasonable window to ship a fix before publishing. We will not pursue legal action against good-faith
research that stays within the scope below.

## Threat model

### What Sunroom is trying to protect

- The contents of your canvases: notes, readable text, image assets, link URLs, window titles, and the positions of
  windows you have placed.
- The fact that you use Sunroom at all, to the extent that a local app can keep that private.
- The integrity of your saved work against crashes, interrupted writes, and partially corrupt files.

### Who the model defends against

- **A network attacker.** Sunroom makes no network requests, so there is no remote surface to attack. There is no
  crash-reporting SDK, analytics SDK, updater feed, or account system to intercept.
- **A casual local observer.** Screen captures are held in memory and are not written to disk. Canvas files live in your
  user's Application Support directory, readable only by your user account (subject to normal POSIX permissions).
- **A corrupted or malicious canvas file.** Canvas JSON is decoded as data only. It cannot execute code, load a plugin,
  or run a script. Importing a canvas assigns it a fresh identity and runs the same validation as a normal load.
- **An interrupted write.** Saves are atomic, the previous file is rotated into `Backups/`, and an unreadable file is
  moved to `Recovered/` rather than deleted.

### What Sunroom does not defend against

- **Malware or another process running as your user.** Such a process can read Application Support, capture your screen,
  and use the same Accessibility APIs Sunroom uses. No unsandboxed local app can prevent that. Use FileVault, keep
  macOS updated, and treat unknown apps as hostile.
- **An attacker with your unlocked account or admin/root access.** Canvas files are not encrypted at rest. FileVault is
  the right control for a stolen disk.
- **Shoulder surfing, screen sharing, or another app recording your screen.** Window cards visibly mirror window
  contents; that is the point. Pause capture and close sensitive windows before sharing your screen.
- **A malicious URL in a link card.** Sunroom stores a URL and opens it only on an explicit user action, in your default
  browser. It does not fetch link previews or resolve URLs over the network.
- **Denial of service through absurd data.** Import is validated and geometry is clamped, but a hand-crafted file with
  enormous coordinates can still make a canvas unpleasant. Report it as a bug; it is not treated as a confidentiality
  issue.

## Permissions

macOS TCC permissions are the most sensitive part of Sunroom. Each is requested only when the feature that needs it is
first used. Sunroom does not request Input Monitoring, Full Disk Access, Automation, Camera, Microphone, Location,
Contacts, or Calendar access.

### Accessibility (`kTCCServiceAccessibility`)

**Why:** to read the position, size, title and identity of other apps' windows, and to move or resize them when you ask
Sunroom to apply a layout.

**What the permission technically allows:** control of the accessibility tree of other applications. macOS does not
scope this per app or per window; the permission is broad. Sunroom's use is narrow and auditable in `SunroomKit`: it
reads window role, subrole, title, position and size, and it sets position and size on the specific windows you have
linked to cards. It does not send keystrokes, read text fields, press buttons in other apps, or enumerate your files.

**What it can reveal:** window titles can contain document names, URLs, or message subjects. Those titles are stored
locally in canvas files when you place a window. They are never transmitted.

**If denied:** the canvas still works as a notes-and-images board. Window nodes cannot be created or moved, and Sunroom
does not repeatedly prompt; macOS manages the prompt and the Settings entry.

### Screen Recording (`kTCCServiceScreenCapture`)

**Why:** to draw live thumbnails of windows you have explicitly placed on the canvas, using ScreenCaptureKit.

**What the permission technically allows:** capture of screen content. Sunroom's capture code subscribes only to the
windows represented by window cards. Menu bar extras, system UI, and Sunroom's own windows are excluded. Captures are
scaled to a capped resolution, kept in memory, and discarded when the card is removed, capture is paused, or the app
quits. They are never written to `Assets/`, never included in backups, and never leave the Mac.

**If denied:** window cards show a placeholder. Notes, images and links are unaffected.

### Verifying these claims

The permission use is confined to `Sources/SunroomKit/`. You can build from source, audit the calls, and run the app
with a network monitor to confirm that it makes no outbound connections. If you find a discrepancy between this
document and the code, that is a security report.

## What is stored, and where

Everything lives under:

```
~/Library/Application Support/Sunroom/
├── Canvases/      one pretty-printed JSON document per canvas, named by UUID
├── Assets/        imported images, named by UUID + original extension
├── Backups/       the previous five versions of each canvas, ISO-8601 timestamped
├── Recovered/     files that failed to decode, kept instead of deleted
├── index.json     reserved for a canvas summary cache (summaries are scanned today)
└── settings.json  local preferences (background, grid, capture paused, window frame)
```

There is no database, no keychain item, no credential, and no hidden cache outside these directories. macOS may also
write standard system logs and, if you have opted in to sharing diagnostics with Apple, crash reports; Sunroom does not
attach canvas contents to those.

To remove all Sunroom data, quit the app and delete the `Sunroom` folder above. Backups are inside it; deleting the app
alone does not delete your work.

## Data that leaves your Mac

None. Specifically:

- No analytics, telemetry, feature flags, or "anonymous usage statistics".
- No crash-reporting SDK.
- No auto-updater and no update check.
- No account, licence check, or device fingerprint.
- The app makes no network requests and links no networking framework. If a future feature needs the network, it will be
  opt-in, documented here before shipping, and off by default.

## Logging

Sunroom uses `os_log` for local diagnostics. Log messages contain counts, error kinds and timing, not note text, image
data, window titles or URLs. Logs stay in the unified logging system on your Mac and are subject to your system's
retention settings.

## Hardening recommendations

- Turn on FileVault. It is the single most effective control for a laptop that leaves your desk.
- Grant Accessibility and Screen Recording only if you use window cards, and revoke them in System Settings when you
  stop using the app.
- Pause capture (`⌃⌘P`) before screen sharing or recording a demo, and remove cards for windows you do not want
  mirrored.
- Keep release builds in `/Applications` rather than running them from `~/Downloads`; a stable path makes TCC grants and
  later updates less confusing.
- Treat canvas files like any other document: they are not encrypted and may contain window titles and private notes.

## Out of scope

- Issues that require an attacker to already have your user account, admin/root, or physical access to an unlocked Mac.
- Vulnerabilities in macOS, ScreenCaptureKit, the Accessibility API, or a third-party app that Sunroom merely calls.
- Social engineering, phishing pages opened from a link card, or problems caused by a malicious canvas that you were
  persuaded to import and then explicitly acted on.
- Missing hardening headers or TLS configuration; Sunroom has no network surface.

If you are unsure whether something is in scope, report it privately and let us decide together.
