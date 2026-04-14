# SimplyMidnight

`SimplyMidnight` is a new Midnight-era WoW addon and companion overlay scaffold.

## What Exists Today

- A standalone WoW addon rooted directly in `Interface/AddOns/SimplyMidnight`
- A spell-registry driven suggestion HUD
- A taint-guard foundation for isolating foreign addon failures
- A basic in-game export strip with spell icons, status cells, and threshold bars
- A starter config window for adding, removing, and reordering suggested spells
- An Electron + Vite overlay shell that can mirror a cropped capture of the WoW client into its own always-on-top window

## Current Goals

- Keep `SimplyMidnight` independent from `SimplyGlad` / `Action` for v1 correctness
- Provide a stable spell-icon surface that GGL can read
- Leave clean adapter seams for future TMW / Action / MetaEngine integration

## Compatibility Strategy

- `SimplyMidnight` now publishes a versioned public bridge snapshot at `_G.SimplyMidnightBridge`.
- The bridge snapshot is capability-probed, not hard-wired to one Action or GGLoader implementation.
- Adapter integration is read-only and version-tolerant: we detect features like toggles, secret runtime pieces, or future MetaEngine surfaces when they exist, and fall back cleanly when they do not.
- Export configuration is also published through the bridge snapshot so future readers can adapt to HUD position, lock state, scale, and protocol version without scraping hard-coded assumptions.
- Blizzard-facing APIs are tracked through a compatibility module, which records available APIs, current build/interface info, and risk flags when important APIs disappear or taint incidents are observed.
- The design goal is that Action / GGLoader can change their Midnight fix independently, and `SimplyMidnight` can adapt through capability negotiation instead of being coupled to one exact implementation.

## Layout

- `SimplyMidnight.toc` and `*.lua` files are the live WoW addon
- `OverlayApp/` is the desktop companion app

## Notes

- The overlay app currently mirrors a manually selected capture region from the WoW window.
- Transparent click-through overlay behavior and MetaEngine integration are reserved for later phases.
