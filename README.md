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

## Layout

- `SimplyMidnight.toc` and `*.lua` files are the live WoW addon
- `OverlayApp/` is the desktop companion app

## Notes

- The overlay app currently mirrors a manually selected capture region from the WoW window.
- Transparent click-through overlay behavior and MetaEngine integration are reserved for later phases.
