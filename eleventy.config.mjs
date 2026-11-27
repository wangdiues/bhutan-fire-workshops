import { readFileSync } from "node:fs";
import { practicals as teachingPlan } from "./practicals.mjs";

const read = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
// Guide section (heading prefix) after which each practical is placed.
const guideSections = {
  wui: { "01-sensitivity": "6.1 ", "02-calibration": "6.2 ", "03-growth": "6.3 ", "04-exposure": "6.4 ",
    "05-fire-mgmt": "6.7 " },
  burn: { "01-severity": "6.5 ", "02-recovery": "6.6 ", "03-cbi-plan": "6.7 " }
};

export default function (config) {
  let md;
  // The guide and its practicals are rendered together inside each course page (course.njk).
  config.ignores.add("src/*-guide.md");
  config.amendLibrary("md", (markdown) => {
    md = markdown;
    markdown.renderer.rules.heading_open = (tokens, index, options, env, renderer) => {
      const name = tokens[index + 1]?.content || "";
      const part = /^Part (\d+)\./.exec(name);
      const id = part ? "part-" + part[1] : name === "Glossary" ? "glossary" :
        name.startsWith("Key references") ? "references" : "";
      if (id) tokens[index].attrSet("id", id);
      return renderer.renderToken(tokens, index, options);
    };
  });
  // Split a course guide into an ordered list of segments so that course.njk can place
  // the synthetic warm-up after Part 3 and each practical at the end of its guide step.
  config.addFilter("guideSegments", (course) => {
    const html = md
      .render(read(`./src/${course.id}-guide.md`).replace(/^---\r?\n[\s\S]*?\r?\n---\r?\n/, ""))
      .replace(/<h1>[\s\S]*?<\/h1>\s*/, "")
      .replaceAll(`href="${course.id}.html#`, 'href="#');
    const headings = [...html.matchAll(/<h([2-6])(?:\s[^>]*)?>([\s\S]*?)<\/h\1>/g)].map((match) => ({
      start: match.index, level: Number(match[1]), text: match[2].replace(/<[^>]+>/g, "").trim(),
    }));
    const sectionEnd = (test, what) => {
      const index = headings.findIndex((heading) => test(heading.text));
      if (index < 0) throw new Error(`No guide heading for ${what} in ${course.id}-guide.md`);
      const next = headings.slice(index + 1).find((heading) => heading.level <= headings[index].level);
      return next ? next.start : html.length;
    };
    const starts = (prefix) => (text) => text.startsWith(prefix);
    const inserts = [];
    const add = (at, segment) => inserts.push({ at, order: inserts.length, segment });
    add(sectionEnd(starts("Part 3."), "the preview"), { type: "preview" });
    for (const practical of course.practicals)
      add(sectionEnd(starts(course.guideSections[practical.folder]), practical.folder), { type: "practical", practical });
    inserts.sort((a, b) => a.at - b.at || a.order - b.order);
    const segments = [];
    let from = 0;
    for (const { at, segment } of inserts) {
      segments.push({ type: "html", html: html.slice(from, at) }, segment);
      from = at;
    }
    segments.push({ type: "html", html: html.slice(from) });
    return segments;
  });
  const release = JSON.parse(read("./src/drive-links.json"));
  if (release.combined.url && !/^https:\/\/drive\.google\.com\//.test(release.combined.url))
    throw new Error("Use a restricted Google Drive URL for the combined package.");
  config.addGlobalData("participantPackage", release.combined);
  const courses = [];
  for (const line of read("./src/courses.txt").trim().split(/\r?\n/)) {
    const [id, title, description] = line.split("|");
    if (!Object.hasOwn(guideSections, id)) throw new Error("Unknown course in courses.txt: " + id);
    {
      const course = { id, title, description, guideSections: guideSections[id], release: release[id] };
      course.demo = read(`./src/examples/${id}-demo.R`);
      course.practicals = teachingPlan.filter((practical) => practical.course === id)
        .map((practical, practicalIndex) => {
          const file = `practical-${practical.folder}.R`;
          const path = `code/${id}/r_studio_run/${file}`;
          const code = read(`./src/${path}`);
          const expected = [
            "Packages are ready.",
            "The correct workshop folder is shown in the Console.",
            "Each named path points to a file in the project.",
            "All required data files are available.",
            "The imported maps or tables appear in Environment.",
            ...practical.expected,
            `teaching_outputs/${practical.folder}.csv is saved in the workshop folder.`,
            "With FALSE the replay is skipped. With TRUE the Console shows a log path and output status.",
          ];
          const blocks = [...code.matchAll(/^# Block (\d{2}): (.+?) ----\r?\n# (.+)$/gm)]
            .map(([, number, title, purpose], index) => ({ number, title, purpose, expected: expected[index] }));
          if (blocks.length !== expected.length) throw new Error("Outdated practical script: " + path);
          const anchor = `practical-${practical.folder}`;
          return { ...practical, path, code, blocks, anchor, href: `#${anchor}`, number: practicalIndex + 1,
            target: "outputs/" + practical.folder, courseTitle: course.title };
        });
      if (course.release.url && !/^https:\/\/drive\.google\.com\//.test(course.release.url))
        throw new Error(`Use a Google Drive link for ${id} in drive-links.json.`);
      courses.push(course);
    }
  }
  config.addGlobalData("courses", courses);
  config.addPassthroughCopy("src/assets");
  config.addPassthroughCopy("src/code/**/*.R");
  config.addPassthroughCopy("src/examples");
  for (const file of ["src/courses.txt", "src/drive-links.json", "src/code/**/*.R", "src/examples/*.R"])
    config.addWatchTarget(file);
  return { dir: { input: "src", output: "_site" } };
}
