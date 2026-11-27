import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { dirname, extname, resolve } from "node:path";

const root = resolve(process.argv[2] || "_site");
const files = readdirSync(root, { recursive: true }).filter((file) => statSync(resolve(root, file)).isFile());
const html = files.filter((file) => file.endsWith(".html"));
const coursePages = ["wui.html", "burn.html"];
if (html.length !== 5 || !coursePages.every((page) => html.includes(page)))
  throw new Error(`Expected the home, setup, downloads and two workshop pages. Found ${html.length} pages.`);

const decode = (text) => text?.replace(/&(amp|quot|lt|gt|#\d+);/g, (_, entity) =>
  entity.startsWith("#") ? String.fromCodePoint(Number(entity.slice(1))) :
    ({ amp: "&", quot: '"', lt: "<", gt: ">" })[entity]);
const same = (shown, code) => shown?.replaceAll("\r\n", "\n") === code.replaceAll("\r\n", "\n");
const shownCode = (content, id) =>
  decode(content?.match(new RegExp(`<code id="${id}">([\\s\\S]*?)</code>`))?.[1]);

// Every practical script appears in full on its workshop page.
const practicals = files.filter((file) => /practical-.*\.R$/.test(file));
if (practicals.length !== 8) throw new Error("Expected one practical per output folder.");
for (const path of practicals) {
  const [, course, name] = /code[\\/](wui|burn)[\\/]r_studio_run[\\/](practical-.*)\.R$/.exec(path);
  const content = readFileSync(resolve(root, `${course}.html`), "utf8");
  const code = readFileSync(resolve(root, path), "utf8");
  const id = "code-" + name;
  if (!same(shownCode(content, id), code) || !content.includes(`data-copy="${id}"`) ||
      (code.match(/^# Block \d{2}/gm) || []).length !== 10)
    throw new Error("The workshop page must contain the full, matching ten-block script: " + path);
}

// Every short-exercise script appears in full, with its download and question.
const exercises = files.filter((file) => /r_studio_run[\\/]lesson-\d-\d\.R$/.test(file));
if (exercises.length !== 33) throw new Error(`Expected 33 short-exercise scripts. Found ${exercises.length}.`);
for (const path of exercises) {
  const [, course, number] = /code[\\/](wui|burn)[\\/]r_studio_run[\\/]lesson-(\d-\d)\.R$/.exec(path);
  const content = readFileSync(resolve(root, `${course}.html`), "utf8");
  const section = content.match(new RegExp(`<details class="lesson" id="lesson-${number}">([\\s\\S]*?)</details>`))?.[1];
  if (!same(shownCode(section, `code-lesson-${number}`), readFileSync(resolve(root, path), "utf8")) ||
      !section.includes("Download R script") || !section.includes("Interpret the result"))
    throw new Error("Incomplete short exercise: " + path);
}

for (const guide of coursePages) {
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
  const ids = new Set([...content.matchAll(/\bid="([^"]+)"/g)].map(([, id]) => id));
  for (const [, link] of content.matchAll(/\b(?:href|src)="([^"]+)"/g)) {
    if (link.startsWith("https://")) continue;
    if (link.startsWith("#")) {
      if (link.length > 1 && !ids.has(link.slice(1))) throw new Error(`Broken in-page link: ${file} → ${link}`);
      continue;
    }
    if (link.startsWith("/") || !existsSync(resolve(dirname(path), link.split(/[?#]/)[0])))
      throw new Error(`Broken or absolute local link: ${file} → ${link}`);
  }
}
console.log(`Verified ${html.length} pages, ${practicals.length} practicals, ${exercises.length} short exercises and all links.`);
