# Mi Band 11 Watchface Shuffle Player

[中文](README.md)

A small Lua reference for shuffle-bag animation playback and visibility management in Mi Band 11 watchfaces using the firmware's Lua / LVGL bridge.

Extracted from an existing watchface with positive feedback on a Mi Band 11. **The extracted module has desktop regression coverage but has not been packaged and tested separately on hardware.**

## Behavior

- One background Image and one fixed-period Timer. All frame paths are prepared once.
- A Fisher–Yates bag starts each clip once per round. With multiple clips, round boundaries never repeat the previous clip.
- Automatic transitions, taps and wake all consume the same queue. An interrupted clip stays consumed.
- Animation runs only when the screen state is exactly `"ON"`, the page is visible, and manual pause is off.
- OFF, AOD and hidden pages pause the timer. A stale callback cannot change hidden frames.
- Resume starts the next queued clip at frame one. Duplicate lifecycle callbacks do not consume additional clips.
- Wake and taps suppress one potentially overdue callback to protect the first frame. Normal automatic transitions have no extra dwell.
- A private Park–Miller RNG avoids global `math.random` and is initialized once per Lua instance.

A single-clip configuration loops that clip. “Once per round” refers to starting a clip, not completing an interrupted clip. Queue and RNG state are not persisted across Lua instance destruction.

## Integration

Copy `src/shuffle_player.lua` into your packer's Lua resources and adapt [examples/main.lua](examples/main.lua). It includes the root, minute subscription, lifecycle hooks and tap binding.

```lua
local ShufflePlayer = require("shuffle_player")

local player = ShufflePlayer.new {
    lvgl = lvgl,
    root = root,
    clips = {
        { prefix = "face", count = 26 },
        { prefix = "w2", count = 30 },
    },
    period_ms = 83,
    seed_salt = 338129365,
    img_path = function(source) return scriptPath .. source end,
}

pageOnPause = function() player:set_page_visible(false) end
pageOnResume = function() player:set_page_visible(true) end

function ScreenStateChangedCB(previous, current, reason)
    player:set_screen_state(current)
end

player:start()
```

The snippet assumes an existing `lvgl`, `root` and resource `scriptPath`. Forward events from any existing lifecycle handlers. Bind taps to `player:skip_next()`. `player:set_paused(boolean)` adds a manual gate; it cannot override screen or page visibility.

Supply your own `face_01.png`, `face_02.png`, `w2_01.png`, etc. `%02d` pads to at least two digits, so frame 100 is `face_100.png`. `extension = "jpg"` is also supported. All clips share a positive integer `period_ms`; their frame counts may differ. `83 ms` is approximately `12.05 fps`.

The default initial screen/page state is visible and ON, matching the source watchface's assumption. Call `start()` promptly after initialization. A delayed first startup may already have an overdue native timer callback; the inherited first-frame protection applies to subsequent resumes and taps. You may provide `screen_on` and `page_visible` booleans to set initial gates.

Optional synchronous hooks:

| Option | Called when |
|---|---|
| `on_clip(index)` | A clip starts, with its actual 1-based configuration index |
| `on_tick()` | A visible timer callback runs, including a protected first-frame callback |
| `on_resume()` | Playback actually starts or resumes |
| `time()` | RNG initialization needs seconds; defaults to `os.time` |

Use `on_clip` for palettes, `on_tick` for dirty cached status, and `on_resume` for refreshing time. Handle overlay errors at the integration boundary, keep callbacks short, and avoid lifecycle reentrancy. Create overlays after constructing the player so that they sit above its background Image.

`seed_salt` is required and must be an integer in `1..2147483646`. It is a build-time salt combined with initialization time, not fresh hardware entropy. Identical salt and initialization time reproduce the sequence. The module requires only the supplied LVGL bridge; `dataman` belongs to the example's clock integration.

## Single-file output

With Python 3.10+:

```bash
python3 tools/bundle.py
python3 tools/bundle.py --entry path/to/main.lua --output dist/main.lua
```

The bundler replaces exactly one standalone `local ShufflePlayer = require("shuffle_player")` line with the module. The resulting entry still needs firmware `lvgl` / `dataman` and your images. It does not produce a `.face` package. Check your packer's resource indices after any changes.

## Tests

Python standard library and Lua 5.1+ are sufficient:

```bash
python3 -m unittest discover -s tests -v
LUA=luajit python3 -m unittest discover -s tests -v
```

The restricted mock models overdue resume callbacks. Tests compare the original, modular and bundled players over 60,000 timer ticks and 6,000 mixed lifecycle events, then exercise bag permutations, frame dwell, single clips, stale callbacks, taps, time refresh, manual pause, invalid inputs and allocation counts.

These tests do not establish device installation, decoder behavior, native memory use or battery cost. The repository contains no original media, fonts, glyph atlases or installable watchface.

The Chinese [behavior notes](docs/behavior.md) and [integration guide](docs/integration.md) explain the timing and evidence boundaries.

## Attribution

Based on the MIT-licensed [AIR-pixel/miband11-watchface-maker](https://github.com/AIR-pixel/miband11-watchface-maker) and local shuffle extensions to its working copy. This is an independent extraction, not an official upstream component. The original MIT notice is retained in [LICENSE](LICENSE); see [NOTICE.md](NOTICE.md).
