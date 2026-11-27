import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { dirname, extname, resolve } from "node:path";

const root = resolve(process.argv[2] || "_site");
const files = readdirSync(root, { recursive: true }).filter((file) => statSync(resolve(root, file)).isFile());
const html = files.filter((file) => file.endsWith(".html"));
const lessons = html.filter((file) => /^(wui|burn)-\d-\d\.html$/.test(file));
if (lessons.length !== 33 || html.length !== 48)
  throw new Error(`Expected 33 short lessons, eight practicals and seven supporting pages. Found ${html.length} pages.`);
const practicals = files.filter((file) => /practical-.*\.R$/.test(file));
if (practicals.length !== 8) throw new Error("Expected one practical per output folder.");
for (const path of practicals) {
  const [, course, name] = /code[\\/](wui|burn)[\\/]r_studio_run[\\/](practical-.*)\.R$/.exec(path);
  const content = readFileSync(resolve(root, `${course}-${name}.html`), "utf8");
  const code = readFileSync(resolve(root, path), "utf8");
  const displayed = content.match(/<code id="full-practical">([\s\S]*?)<\/code>/)?.[1]
    .replace(/&(amp|quot|lt|gt|#\d+);/g, (_, entity) =>
      entity.startsWith("#") ? String.fromCodePoint(Number(entity.slice(1))) :
        ({ amp: "&", quot: '"', lt: "<", gt: ">" })[entity]);
  if (displayed?.replaceAll("\r\n", "\n") !== code.replaceAll("\r\n", "\n") ||
      !content.includes('data-copy="full-practical"') || (code.match(/^# Block \d{2}/gm) || []).length !== 10)
    throw new Error("The HTML must contain the full, matching ten-block script: " + path);
}
for (const guide of ["wui.html", "burn.html"]) {
  const content = readFileSync(resolve(root, guide), "utf8");
  for (let part = 1; part <= 8; part++)
    if (!content.includes(`id="part-${part}"`)) throw new Error(`Missing part ${part} in ${guide}`);
}

for (const file of files) {
  const path = resolve(root, file);
  const ext = extname(file);
  if (["assets/wui-demo.png", "assets/burn-demo.png"].includes(file.replaceAll("\\", "/"))) continue;
  if (/^assets\/(wui|burn)\/fig_\d{2}_[a-z0-9_]+\.png$/.test(file.replaceAll("\\", "/"))) continue;
  if (![".html", ".R", ".Rproj", ".css", ".js"].includes(ext))
    throw new Error("Unexpected file in the public artifact: " + file);
  const content = readFileSync(path, "utf8");
  if (/DOFPS_\d{4}_[A-Z0-9]+|(?:[A-Z]:[\\/](?:Users|20\d{2}))/i.test(content))
    throw new Error("Private identifier or machine path: " + file);
  if (ext !== ".html") continue;
  for (const [, link] of content.matchAll(/\b(?:href|src)="([^"]+)"/g)) {
    if (/^(https:\/\/|#)/.test(link)) continue;
    if (link.startsWith("/") || !existsSync(resolve(dirname(path), link.split(/[?#]/)[0])))
      throw new Error(`Broken or absolute local link: ${file} → ${link}`);
  }
}
for (const file of lessons) {
  const content = readFileSync(resolve(root, file), "utf8");
  if (!content.includes("Download R script") || !content.includes("Interpret the result"))
    throw new Error("Incomplete lesson: " + file);
}
console.log(`Verified ${html.length} pages, ${lessons.length} lesson downloads and all relative links.`);
