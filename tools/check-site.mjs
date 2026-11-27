import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { dirname, extname, resolve } from "node:path";

const root = resolve("_site");
const files = readdirSync(root, { recursive: true }).filter((file) => statSync(resolve(root, file)).isFile());
const html = files.filter((file) => file.endsWith(".html"));
const lessons = html.filter((file) => /^(wui|burn)-\d-\d\.html$/.test(file));
if (lessons.length !== 33 || html.length !== 38)
  throw new Error(`Expected 33 lesson pages and 5 supporting pages, found ${lessons.length} and ${html.length - lessons.length}.`);

for (const file of files) {
  const path = resolve(root, file);
  const ext = extname(file);
  if (["assets/wui-demo.png", "assets/burn-demo.png"].includes(file.replaceAll("\\", "/"))) continue;
  if (![".html", ".R", ".Rproj", ".css", ".js"].includes(ext))
    throw new Error("Unexpected file in the public artifact: " + file);
  const content = readFileSync(path, "utf8");
  if (/DOFPS_\d{4}_[A-Z0-9]+|(?:[A-Z]:[\\/](?:Users|20\d{2}))/i.test(content))
    throw new Error("Private identifier or machine path: " + file);
  if (ext !== ".html") continue;
  for (const [, link] of content.matchAll(/\b(?:href|src)="([^"]+)"/g)) {
    if (/^(https:\/\/|#)/.test(link)) continue;
    if (link.startsWith("/") || !existsSync(resolve(dirname(path), link.split("#")[0])))
      throw new Error(`Broken or absolute local link: ${file} → ${link}`);
  }
}
for (const file of lessons) {
  const content = readFileSync(resolve(root, file), "utf8");
  if (!content.includes("Download R script") || !content.includes("Interpret the result"))
    throw new Error("Incomplete lesson: " + file);
}
console.log(`Verified ${html.length} pages, ${lessons.length} lesson downloads and all relative links.`);
