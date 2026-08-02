# Screenshots and GIFs

The images the root README embeds. Drop captures here **at exactly these names** — the
markup already points at them, so nothing else needs editing.

> **Read every shot before committing it.** This tool's whole job is displaying the data an
> app handles, so a screenshot of it is a screenshot of that data. Things that have already
> turned up in practice: the machine hostname on the Device page, a real name typed into a
> Hive box during testing, and request headers shown verbatim in the Network pane. All are
> invisible while you're looking at your own tool and permanent once pushed.

| File | What it shows | Priority |
|---|---|---|
| `network.png` | The request list with a mix of statuses — a green 200, a red 404/500 — and the detail pane open on the right. | required |
| `logs.png` | The **error-detail dialog** open: exception, context Fields, stack trace. Better than plain scrolling logs — it shows the structured context, which is the part you can't guess from a list. | required |
| `timeline.png` | Several lanes populated, ideally with a jank marker visible. | required |
| `storage.png` | A value **mid-edit**, not a read-only scroll — the editor is the feature, and the README caption says "browse *and* edit". A `List` as chips or a bool as a switch shows "types preserved" better than a JSON blob does. | required |
| `state.png` | The **Changes** diff (red `-` / green `+`) is what sells this page, plus several sources in the left list so it's clear bloc and Riverpod share it. Capture early, while the counter is low — a long `history` field crowds the diff out of frame. | required |
| `visual.png` | A flag switched on, so the warning banner shows. | required |
| `export.png` | The report preview open, with the section toggles visible. **The report embeds the Device section**, so the same hostname caveat as `device.png` applies — and it embeds captured request headers, which are verbatim unless `hideHeaders` is set. | required |
| `hero.gif` | Drag the floating button, open the panel, switch a tab or two. | required |
| `device.png` | The Device page. **Check the `Computer` row before publishing** — on desktop it's your machine's hostname. Capture on an emulator, or edit that row out. A shot reading `Platform: android` also sells a mobile tool better than `windows`. | optional |
| `mocks.png` | A rule in the editor, with a `MOCKED` badge behind it. | optional |

`device.png` and `mocks.png` aren't referenced by the README yet — add them and I'll wire
them in, or skip them.

## Capturing

The example app wires every integration and has buttons that generate traffic, logs, state
changes and jank:

```
cd example && flutter run -d windows
```

Use its load generator to fill the pages before capturing — an empty page shows nothing worth
looking at.

### Conventions

- **Crop to the overlay panel.** Cut the Windows title bar, the desktop background and the
  host app behind it. The panel is the product; the chrome is dead pixels that survive
  downscaling badly.
- **One window size for everything.** Mixed aspect ratios in a gallery look accidental.
- **Downscale to ~1400px wide** before committing. These render at a few hundred px in
  practice and a full-res 1920px PNG is wasted bytes in every clone.
- **Keep `hero.gif` under ~3 MB.** 10–15s at 12–15fps covers drag → open → tab.
- **No real data.** Captures go on a public page. The example's fake traffic against
  `jsonplaceholder` / `httpbin` is the point — don't capture against a real backend. Note the
  Network detail pane shows request headers **verbatim** unless `hideHeaders` is set, so a
  real `authorization` value would be published along with the screenshot.

### GIF from a screen recording

```
ffmpeg -i recording.mp4 -vf "fps=14,scale=1000:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse" -loop 0 hero.gif
```

The `palettegen`/`paletteuse` pair is what keeps a UI GIF from banding — the default 256-colour
quantiser makes flat panel backgrounds look blotchy.
