# Keyboard reference

Sunroom is designed to be usable without the mouse. This is the complete list of bindings. If a shortcut is not here,
it is not bound — the command palette (`⌘K`) is the escape hatch for everything else.

Conventions:

- **Return** means the Return key, **⌫** means Delete (Backspace on some keyboards), **Esc** means Escape.
- Modifiers appear in Apple's order: Control (⌃), Option (⌥), Shift (⇧), Command (⌘).
- Text fields win. While you are typing in a note, the search field or the palette, ordinary keys and `⌘A` go to the
  text field. App-level shortcuts such as `⌘K` still work.
- Arrow-key nudging and Delete apply to the current selection, never to the text cursor.

## Canvas mode

Canvas mode puts every window on the current display on one plane. It is the headline interaction, so it has the
shortest keys.

| Shortcut | Action |
| --- | --- |
| `⌃⌥Space` | Put the windows on a canvas / return to the canvas / leave canvas mode |
| `⌃⌥⇧Space` | Back to the zoomed-out plane from a focused window |
| `Esc` | Leave canvas mode and restore every window to its original frame |
| `F` | Fit every window on the plane |
| `↑ ↓ ← →` | Select the nearest window in that direction |
| `↩` | Go into the selected window (fills the screen) |
| `Tab` / `⇧Tab` | Cycle the selection |
| Two-finger scroll | Pan the plane |
| Pinch | Zoom around the pointer (clamped to the app minimums) |
| Double-tap | Fit everything |
| Drag a window | Move it on the plane |
| Drop on a screen edge | Tile: left, right, top, bottom or a quarter |
| Drop on another window | Stack it, offset like a paper pile |
| `⌥` + scroll | Zoom with a mouse |

While canvas mode is on, a transparent overlay above every window owns the pointer; apps below do not receive clicks
until you go into one. `Esc` or `⌃⌥Space` gives the desktop back exactly as it was.

## App

| Shortcut | Action |
| --- | --- |
| `⌘K` | Open the command palette |
| `⌘F` | Search the canvas (opens the palette in object mode) |
| `⌘,` | Settings |
| `⌘/` | This shortcut list |
| `⌘S` | Save now (autosave is already on) |
| `⌘Q` | Quit |
| `⌥Space` | Summon Sunroom from any app (global; configurable in Settings) |
| `⌘H` | Hide Sunroom, leaving the desktop as it was |

## Files

| Shortcut | Action |
| --- | --- |
| `⌘⇧N` | New canvas |
| `⌘N` | New note at the centre of the viewport |
| `⌘⇧T` | New text card |
| `⌘⇧G` | New frame |
| `⌘I` | Add an image from disk |
| `⌘⇧E` | Export the canvas as a PNG |
| `⌘⇧I` | Import a canvas (`.json`) |

## Canvas navigation

| Shortcut | Action |
| --- | --- |
| Two-finger scroll | Pan |
| `Space` + drag | Pan with the hand tool |
| Middle-button drag | Pan (mouse) |
| `H` | Arm the hand tool |
| Pinch | Zoom around the pointer |
| `⌘` + scroll | Zoom around the pointer |
| `⌘=` | Zoom in around the usable viewport centre |
| `⌘-` | Zoom out |
| `⌘0` | Actual size (100%) |
| `⇧⌘F` | Fit everything |
| `⌥⌘F` | Fit the selection |
| Double-tap with two fingers | Zoom to the item under the pointer, or fit everything |
| `⌘⇧M` | Show or hide the minimap |
| `⌥⌘G` | Show or hide the grid |

Panning and zooming change the camera only. Node positions live in canvas space and never move as a side effect.

## Selecting and moving

| Shortcut | Action |
| --- | --- |
| Click | Select an item |
| `⇧` or `⌘` + click | Add to, or remove from, the selection |
| Drag on empty canvas | Marquee-select items fully inside the rectangle |
| `⌘A` | Select all unlocked items |
| `⌘⇧A` or `Esc` | Clear the selection |
| `Tab` / `⇧Tab` | Select the next / previous item |
| `↑ ↓ ← →` | Nudge by 1 point |
| `⇧` + arrows | Nudge by 10 points |
| `⌘D` | Duplicate |
| `⌫` | Delete |
| `⌘C` / `⌘V` | Copy / paste (each paste offsets by 24 points) |
| `⌘X` | Cut |
| Drag a selection | Move; hold `⇧` to lock to one axis |
| Drag a selection handle | Resize |
| `⌘G` | Group the selection into a frame |
| `⌘⇧G` | Ungroup |
| `⌥⌘T` | Tidy everything into a grid |

## Editing

| Shortcut | Action |
| --- | --- |
| Double-click a note or text card | Edit in place |
| `Return` | Edit the selected card |
| `Esc` | Commit and close the editor |
| Click away | Commit the edit |
| `⌘Z` / `⌘⇧Z` | Undo / redo |
| `⌘V` with an image on the clipboard | Paste the image onto the canvas |

## Arranging

| Shortcut | Action |
| --- | --- |
| `⌥⌘I` | Show or hide the inspector |
| Inspector → Align | Six alignment modes for a multi-selection |
| Inspector → Distribute | Equal gaps, horizontally or vertically |
| Inspector → Arrange | Grid, rows, columns or radial |
| Right-click an item | Context menu with colour, z-order, lock and per-kind actions |

## Windows

| Shortcut | Action |
| --- | --- |
| `⇧⌘W` | Windows on this Mac (the window library) |
| `⌃⌥C` | Capture the desktop as window cards |
| `⌘R` | Refresh the window list |
| `Return` on a window card | Fly to the real window (hides Sunroom) |
| Right-click a window card | Focus, move here, centre, full screen, minimise, close |
| Dragging a window card | Move the card; use **Apply Layout to Desktop** to move the real window |

Window commands require Accessibility permission. Screen previews additionally require Screen Recording permission.
Both are explained in Settings → Windows.
