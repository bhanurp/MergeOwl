# MergeOwl website

This directory contains the static website for https://mergeowl-eight.vercel.app.
Edit `index.html`, `style.css`, or files in `assets/` here for website changes.
The separate `sites/mergeowl` checkout is the original ChatGPT Sites copy;
changes there do not update this directory automatically.

## Vercel Git integration

- Repository: `bhanurp/MergeOwl`
- Vercel project: `mergeowl` in `bhanus-projects-7d42068a`
- Root directory: `website`
- Production branch: `master`
- Framework preset: Other
- Build command: empty
- Install command: empty
- Output directory: `.`

Once the repository is connected in Vercel, pushes to `master` deploy production.
Other branches create preview deployments according to Vercel's Git settings.
No Vercel token or GitHub Actions deployment workflow is required.

## Local preview

From the repository root, run `python3 -m http.server 4175 --directory website`
and open http://localhost:4175.
