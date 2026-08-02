# Screenshots and GIFs

The images the root README embeds. Drop captures here **at exactly these names** — the
markup already points at them, so nothing else needs editing.

| File | What it shows |
|---|---|
| `hero.gif` | The pitch: drag the floating button, open the panel, switch a tab or two. |
| `timeline.png` | The Timeline with a few lanes populated, ideally including a jank marker. |
| `network.png` | The Network list with a mix of statuses — a green 200 and a red 4xx/5xx. |
| `logs.png` | The Logs page with a few levels visible, and an error folded in. |
| `state.png` | The State page mid-transition, showing a change history. |
| `storage.png` | The Storage page with a value being edited (the chips list reads well). |
| `visual.png` | The Visual page with a flag on, so the warning banner is visible. |
| `device.png` | The Device page. |
| `export.png` | The Export page with the preview open. |
| `mocks.png` | A mock rule in the editor, plus a `MOCKED` badge in the list behind it. |

## Capturing

The example app wires every integration and has buttons that generate traffic, logs, state
changes and jank:

```
cd example && flutter run
```

Use its load generator to fill the pages before capturing — an empty page shows nothing worth
looking at.

### Conventions

- **One device for everything.** Mixed aspect ratios in a gallery look accidental.
- **Dark mode**, unless the light one photographs better. The overlay is a dark surface; a
  light host app behind it makes the panel edge read clearly.
- **Portrait phone**, ~1080px wide. Downscale to **≤ 900px** before committing — these render
  in a Markdown table at a few hundred px and a full-res PNG is wasted bytes in every
  `pub get`.
- **Keep `hero.gif` under ~3 MB.** It's in the published archive, so it's a download cost for
  every user. 10–15s at 12–15fps is plenty for drag → open → tab.
- **No real data.** Captures go on a public page. The example app's fake traffic is the point;
  don't capture against a real backend with live tokens, and note the Network pane shows
  headers verbatim unless `hideHeaders` is set.

### GIF from a screen recording

```
ffmpeg -i recording.mp4 -vf "fps=14,scale=900:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse" -loop 0 hero.gif
```

The `palettegen`/`paletteuse` pair is what keeps a UI GIF from banding — the default 256-colour
quantiser makes flat panel backgrounds look blotchy.
