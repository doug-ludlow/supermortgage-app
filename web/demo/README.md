# Website demo

Records the HTML prototype (`docs/prototype/Supermortgage-Agent-Prototype.html`) being walked through, the way the app's own walk goes: sign-up, meeting the agent, the three connections, the number, one approval, the feed, work, goals, artifacts, the refinance hand-off, permissions and memory, dark mode, a question, pause.

Two outputs, both silent, in `out/`:

| File | Size | Use |
| --- | --- | --- |
| `supermortgage-demo-16x9.mp4` / `.webm` / `-poster.jpg` | 1920×1080 | The product page: captions on the left, the phone on the right. |
| `supermortgage-demo-9x16.mp4` / `.webm` / `-poster.jpg` | 780×1688 | Phone-only, for a narrow column or a story format. |

## Record

Needs Node 22, ffmpeg on the PATH, and the Inter font installed (the prototype's own font stack; set `DEMO_FONT` to use another installed face).

```sh
cd web/demo
npm install
npx playwright install chromium   # once
npm run record                    # both formats; or record:16x9 / record:9x16
node record.mjs --no-encode       # the raw WebM only, for a quick look
node record.mjs --poster          # retake the two poster stills, no video
```

A run takes about five minutes: two walks of roughly 100 seconds each, then the encodes.

## Edit

- Captions, pacing and what gets tapped live in the `script` array in `record.mjs`. Each step is one action with an optional caption and pause; `poster: true` marks the step whose frame becomes the poster.
- The stage layout (type sizes, the phone bezel, the chapter marks) is `stage.html`. `phone.html` is the 9:16 frame.
- The prototype is served as is, except that its `env(safe-area-inset-*)` values are replaced with an iPhone 15's (59pt top, 34pt bottom) so the layout matches the device. The status bar, dynamic island and home indicator are injected by `record.mjs`; the prototype file itself is never changed.
