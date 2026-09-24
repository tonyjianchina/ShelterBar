# ShelterBar website

Static official website for ShelterBar. The public assets are in `dist/`.

```sh
python3 -m http.server 4178 --directory dist
```

The download links target the tagged v0.3.1 GitHub preview release explicitly.
Update all matching links and version text together for a new release.
The autoplay shelf is a labeled illustration, not a native app screenshot.
It opens an empty shelf and drags three menu-bar glyphs into it in a loop.
The animation pauses offscreen, supports a pause control, and shows its final
state when reduced motion is requested.

Local Sites configuration lives in `.openai/hosting.json`; this repository snapshot
omits service identity and credentials. The product uses no external web fonts,
analytics, third-party scripts, or account sign-in.
