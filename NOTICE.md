# Attribution

The Lua / LVGL watchface integration and baseline generated script are derived from
[AIR-pixel/miband11-watchface-maker](https://github.com/AIR-pixel/miband11-watchface-maker),
whose MIT license and original copyright notice are retained in `LICENSE`.

The shuffle player was a local extension to that project's working copy. This
repository extracts that extension into a configurable module, with an integration
example, desktop regression harness, bundling helper and documentation. It is not
an official component of the upstream project.

`tests/fixtures/original-main.lua` preserves the original generated player for
behavioral comparison. It contains no original animation frames or font files.

This repository is distributed under the MIT license in `LICENSE`. The license
does not grant rights to media or fonts supplied separately by watchface authors.
