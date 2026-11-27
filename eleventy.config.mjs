import { readFileSync, readdirSync } from "node:fs";
import { practicals as teachingPlan } from "./practicals.mjs";

const read = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const runs = {
  wui: [
    ["02", "WUI layers", "Grid, footprints and vegetation rasters", "data/derived/layers and outputs/01-sensitivity", "Compare the five structural classes and the vegetation sensitivity runs."],
    ["03", "Historical fire association", "Stage 02 and fire evidence", "data/derived/wui_thimphu.gpkg and outputs/02-calibration", "Compare in-sample and held-out Youden J. Historical proximity is evidence of association."],
    ["04", "Settlement-proxy change", "Stages 02–03 and annual Dynamic World shares", "data/derived/wui_annual_dynamic_world.csv and outputs/03-growth", "Read the complete years separately from partial-year context. The trend measures a settlement proxy."],
    ["05", "Exposure and field kit", "Stage 03, population, access and susceptibility", "outputs/04-exposure and data/derived/field_kit", "Read population as an estimate and keep generated map labels out of observer forms."],
    ["08", "Scientific review audit", "Stages 02–05", "data/derived/results_review_audit.json", "Check the effect of thresholds, evidence sources and ranking choices on conclusions."]
  ],
  burn: [
    ["02", "Detection and spectral change", "Incident inventory, paired imagery, land cover and thermal evidence", "data/derived/burn_severity_paro_thimphu.gpkg and outputs/01-severity", "The reviewed baseline has 91 incident–sensor pairs. A pair without downloaded post-fire imagery is excluded. The classes describe provisional spectral change."],
    ["03", "Spectral trajectories", "Stage 02 or reviewed starter maps, and annual Landsat NBR", "data/derived/incident_spectral_trajectory_summary.csv and outputs/02-recovery", "Interpret changes relative to the reference ring and pre-fire baseline as spectral trajectories."],
    ["04", "Field design", "Stage 02 or reviewed starter maps, terrain and access inputs", "data/derived/field_plan and outputs/03-cbi-plan", "Use calibration plots to relate field observations to mapped change. Use the independent probability sample to estimate accuracy."]
  ]
};

export default function (config) {
  let md;
  // Each guide is rendered inside its course page (see course.njk); <id>-guide.html only redirects.
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
  // Render a guide's Markdown (front matter removed) for embedding in its course page.
  config.addFilter("guideHtml", (id) => md
    .render(read(`./src/${id}-guide.md`).replace(/^---\r?\n[\s\S]*?\r?\n---\r?\n/, ""))
    .replace(/<(\/?)h1>/g, "<$1h2>").replaceAll(`href="${id}.html#`, 'href="#'));
  const release = JSON.parse(read("./src/drive-links.json"));
  if (release.combined.url && !/^https:\/\/drive\.google\.com\//.test(release.combined.url))
    throw new Error("Use a restricted Google Drive URL for the combined package.");
  config.addGlobalData("participantPackage", release.combined);
  const installer = read("./src/start/01_Install_Workshop_Packages.R");
  config.addGlobalData("installer", installer);
  config.addGlobalData("packageDescriptions", [...installer.matchAll(/^  (\w+) = "([^"]+)",?$/gm)]
    .map(([, name, description]) => ({ name, description })));
  const courses = [];
  let course;
  for (const line of read("./src/courses.txt").trim().split(/\r?\n/)) {
    const [id, title, description, expected, question] = line.split("|");
    if (Object.hasOwn(runs, id)) {
      course = { id, title, description, stages: runs[id], lessons: [], release: release[id] };
      course.demo = read(`./src/examples/${id}-demo.R`);
      course.stageFiles = readdirSync(new URL(`./src/code/${id}/scripts/`, import.meta.url));
      course.helperFiles = readdirSync(new URL(`./src/code/${id}/R/`, import.meta.url));
      course.practicals = teachingPlan.filter((practical) => practical.course === id)
        .map((practical) => {
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
          return { ...practical, path, code, blocks, href: `${id}-practical-${practical.folder}.html`,
            target: "outputs/" + practical.folder, courseTitle: course.title };
        });
      if (course.release.url && !/^https:\/\/drive\.google\.com\//.test(course.release.url))
        throw new Error(`Use a Google Drive link for ${id} in drive-links.json.`);
      courses.push(course);
    } else {
      const filename = `lesson-${id.replace(".", "-")}.R`;
      const href = `${course.id}-${id.replace(".", "-")}.html`;
      const script = `code/${course.id}/r_studio_run/${filename}`;
      const code = read(`./src/${script}`);
      course.lessons.push({ id, title, inputs: description, expected, question, href, script, code, filename });
    }
  }
  const lessons = courses.flatMap((currentCourse) => currentCourse.lessons.map((lesson, index) => ({
    ...lesson,
    courseId: currentCourse.id,
    courseTitle: currentCourse.title,
    previous: currentCourse.lessons[index - 1]?.href,
    next: currentCourse.lessons[index + 1]?.href,
  })));
  config.addGlobalData("courses", courses);
  config.addGlobalData("lessons", lessons);
  config.addGlobalData("practicals", courses.flatMap((course) => course.practicals.map((practical, index) => ({
    ...practical, previous: course.practicals[index - 1]?.href, next: course.practicals[index + 1]?.href,
  }))));
  config.addPassthroughCopy("src/assets");
  config.addPassthroughCopy("src/code/**/*.R");
  config.addPassthroughCopy("src/code/**/*.Rproj");
  config.addPassthroughCopy("src/examples");
  config.addPassthroughCopy("src/start/*.R");
  for (const file of ["src/courses.txt", "src/drive-links.json", "src/code/**/*.R", "src/examples/*.R"])
    config.addWatchTarget(file);
  return { dir: { input: "src", output: "_site" } };
}
