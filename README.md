# Bhutan forest fire workshops

This repository builds the public teaching pages, annotated R scripts and synthetic examples for the two FIRE–BHUTAN workshops.

## Build and preview

```sh
npm ci
npm run build
npm test
```

Open `_site/index.html` to preview the offline site. For GitHub Pages, set **Settings → Pages → Source** to **GitHub Actions** and push to `main`. The workflow builds and checks the HTML before publishing.

## Participant materials

The organizer uploads the combined project ZIP to Google Drive and grants Viewer access to approved participants. Set `combined.url` in `src/drive-links.json` and deploy. The site and public scripts work before the restricted link is supplied.

The detailed HTML guides adapt the workshop PDFs. In the analysis workspace, regenerate their Markdown with `node scripts/prepare_workshop_guides.mjs`. Edit `practicals.mjs` for the beginner method notes and code. Run `node scripts/prepare_beginner_practicals.mjs` to write the eight complete scripts to the workshop folders, then `node scripts/prepare_training_release.mjs --combined` to sync public scripts and assemble the participant project. Include the verified site build as `lessons/` in that project when archiving for offline training.

The public repository carries teaching content, R source and reviewed figures appropriate for public use. Workshop datasets, incident identifiers and example configuration stay in the organizer’s participant package. The scientific stage scripts and reviewed results remain the baseline. The combined package also contains the approved derived NFI fuel input used by the burn fuel models. WUI fire-management figures use the existing participant-package hillshade setting for offline rendering.
