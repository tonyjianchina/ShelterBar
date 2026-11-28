# ShelterBar website

Static official website for ShelterBar. The public assets are in `dist/`.

```sh
python3 -m http.server 4178 --directory dist
```

The download links target the tagged v0.5.14 GitHub release explicitly; the current package is build 38.
The release is prepared as a draft, without the pre-release flag. Do not deploy
this website update until the maintainer has reviewed the draft and approved deployment.
Update all matching links and version text together for a new release.
The autoplay shelf is a labeled illustration, not a native app screenshot.
It opens an empty shelf and drags three menu-bar glyphs into it in a loop.
The animation pauses offscreen, supports a pause control, and shows its final
state when reduced motion is requested.

Local Sites configuration lives in `.openai/hosting.json`; this repository snapshot
omits service identity and credentials. The product uses no external web fonts,
analytics, third-party scripts, or account sign-in.

`dist/privacy/index.html` is the Chinese and English privacy policy. The live
sites still serve the marketing homepage for `/privacy` until this file is
deployed and the host serves it instead of falling back to `index.html`. Do not
deploy from this repository snapshot; the maintainer publishes the site.

The canonical policy URL is **https://shelterbar.zhengjian.me/privacy**.
The policy uses root-relative stylesheet and home links so both `/privacy` and
`/privacy/` work. Deploy all of `dist/`, not the policy HTML alone. The VPS must
serve `/privacy` as `privacy/index.html` (or redirect to `/privacy/`) before its
SPA fallback. A sample Nginx location for the maintainer, not applied here:

```nginx
location = /privacy { return 308 /privacy/; }
location /privacy/ { try_files $uri $uri/ =404; }
```

After deployment, verify the document title is `ShelterBar 隐私政策 · Privacy
Policy`, both language sections and the CSS load, and the URL does not return the
marketing homepage. No deployment is authorized by this change.
