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

The organizer uploads the curated project ZIPs to Google Drive and grants Viewer access to approved participants. Add their URLs in `src/drive-links.json` and deploy to update the two download buttons. The course pages and code downloads also work before the URLs are supplied.

The detailed HTML guides adapt the workshop PDFs and replace the launcher commands with RStudio steps. Regenerate their Markdown and reviewed aggregate figures in the original analysis workspace with `node scripts/prepare_workshop_guides.mjs`. Each `practical-*.R` file matches a named output folder and uses the corresponding real-data package.

The public repository carries teaching content and R source. Workshop datasets, prepared outputs, incident identifiers and example configuration belong in the organizer's reviewed participant packages. In the original analysis workspace, edit lessons under the workshop's `r_studio_run/` folder, then run `node scripts/prepare_training_release.mjs` to refresh the public copies. Add `--packages` to assemble curated project folders for a new release. Archive those folders locally for organizer review and Drive distribution.
