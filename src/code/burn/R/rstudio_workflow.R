# RStudio orchestration only. Existing scientific calculations are unchanged.
# All paths inspected by this helper are inside the open project folder.
.workflow_root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)

.workflow_spec <- function() {
  if (!requireNamespace("jsonlite", quietly = TRUE))
    stop("Install jsonlite in this R project first: install.packages('jsonlite')")
  cfg <- jsonlite::read_json(file.path(.workflow_root, "config/settings.json"))
  wui <- identical(cfg$package, "thimphu_WUI")
  if (!wui && !identical(cfg$package, "thimphu_paro_burn_severity"))
    stop("Open one of the supplied .Rproj files before sourcing START_HERE.R.")
  stages <- if (wui) c(`02` = "02_wui_layers.R", `03` = "03_fire_calibration.R",
    `04` = "04_wui_growth.R", `05` = "05_exposure_fieldkit.R",
    `08` = "08_scientific_revision.R", `15` = "15_firelines_rxburn.R",
    `16` = "16_fire_mgmt_figures.R", `17` = "17_field_validation_kit.R") else c(`02` = "02_severity_mapping.R",
    `03` = "03_post_fire_recovery.R", `04` = "04_cbi_field_plan.R")
  packages <- c("terra", "sf", "jsonlite", "ggplot2", "patchwork", "ggspatial",
    "openxlsx", "ragg", "png", "systemfonts", "scales")
  if (!wui) packages <- c(packages, "ggrepel", "exactextractr", "lme4", "emmeans", "spdep")
  list(cfg = cfg, wui = wui, stages = stages, packages = packages,
    defaults = if (wui) c("02", "03", "04", "05", "08") else c("02", "03", "04"))
}

check_project <- function(stages = NULL) {
  spec <- .workflow_spec()
  if (is.null(stages)) stages <- spec$defaults
  if (!length(stages) || anyDuplicated(stages) || any(!stages %in% names(spec$stages)))
    stop("Choose unique stage IDs from: ", paste(names(spec$stages), collapse = ", "))
  if (is.unsorted(match(stages, names(spec$stages)))) stop("Supply stages in dependency order.")
  packages <- spec$packages
  if (any(stages %in% c("15", "16"))) packages <- c(packages, "lpSolve", "lwgeom")
  if ("17" %in% stages) packages <- c(packages, "zip")
  installed <- rownames(installed.packages())
  missing_packages <- setdiff(packages, installed)
  need <- c("config/settings.json", file.path("scripts", unname(spec$stages[stages])))
  if (spec$wui) {
    need <- c(need, file.path("data/inputs", c("study_area.gpkg", "grid_50m.tif",
      "gewog_50m.tif", "buildings.gpkg", "vegetation_shares_50m.tif", "forest_type_50m.tif",
      "population_2020_50m.tif", "roads_osm.gpkg", "walk_time_h_50m.tif",
      "susceptibility_class_50m.tif", "fire_evidence.gpkg",
      sprintf("dynamic_world/dw_%d_shares_50m.tif", 2016:2026))))
    if (!"02" %in% stages && any(stages %in% c("03", "04", "08")))
      need <- c(need, "data/derived/layers/density_ob.tif")
    if (!"03" %in% stages && any(stages %in% c("04", "05", "08", "15", "16")))
      need <- c(need, "data/derived/wui_thimphu.gpkg", "data/derived/results_calibration.json",
        "data/derived/wui_class_calibrated_50m.tif")
    if (any(stages %in% c("15", "16", "17"))) need <- c(need, file.path("data/inputs/fire_mgmt",
      c("layers.gpkg", "dem_50m.tif", "slope_deg_50m.tif", "aspect_deg_50m.tif",
        "fuel_50m.tif", "private_land_cover_50m.tif", "bare_pct_50m.tif", "soil_type_50m.tif")))
    if ("16" %in% stages && !"15" %in% stages)
      need <- c(need, "data/derived/fire_mgmt/run_state.rds")
    if ("17" %in% stages && !"15" %in% stages)
      need <- c(need, "data/derived/fire_mgmt/fire_management_thimphu.gpkg",
        "data/derived/fire_mgmt/shp/thimphu_gewogs.shp")
  } else {
    need <- c(need, file.path("data/inputs", c("study_area.gpkg", "dem_30m.tif",
      "forest_type_50m.tif", "walk_time_to_road_h_100m.tif",
      "dofps_incidents_paro_thimphu.csv", "event_imagery_inventory.csv",
      "validation/firms_points.csv", "validation/mcd64a1_burned_pixels.csv",
      "validation/worldcover2021_30m.tif")))
    if ("02" %in% stages) need <- c(need,
      sprintf("data/inputs/validation/dw_label_30m_%d.tif", 2017:2024))
    inv_file <- file.path(.workflow_root, "data/inputs/event_imagery_inventory.csv")
    if ("02" %in% stages && file.exists(inv_file)) {
      inv <- read.csv(inv_file)
      available <- inv[which(inv$status == "downloaded"), ]
      pre <- unique(available[which(available$phase == "pre"), c("event_id", "sensor")])
      post <- unique(available[which(available$phase == "post"), c("event_id", "sensor")])
      pairs <- merge(pre, post, by = c("event_id", "sensor"))
      listed <- unique(inv[c("event_id", "sensor")])
      omitted <- nrow(listed) - nrow(pairs)
      message(sprintf("Imagery inventory: %d complete pairs, %d without both downloaded phases.",
        nrow(pairs), omitted))
      if (!nrow(pairs)) stop("No complete pre/post imagery pairs are marked downloaded.")
      keys <- paste(pairs$event_id, pairs$sensor, sep = "_")
      for (suffix in c("_pre.tif", "_post.tif", "_pre.json", "_post.json"))
        need <- c(need, file.path("data/raw/events", paste0(keys, suffix)))
      # Require the documented seasonal inputs, rather than silently accepting widespread fallback.
      for (suffix in c(".tif", ".json"))
        need <- c(need, file.path("data/raw/events_seasonal", paste0(keys, suffix)))
    }
    if ("03" %in% stages) need <- c(need,
      sprintf("data/raw/landsat_annual_nbr/landsat_nbr_%d.tif", 2012:2025))
    if (!"02" %in% stages && any(stages %in% c("03", "04")))
      need <- c(need, "data/derived/burn_severity_paro_thimphu.gpkg")
    message("Burn stages also build section PDFs with the existing report helper; release/Word steps are excluded.")
  }
  missing_files <- unique(need[!file.exists(file.path(.workflow_root, need))])
  # Parse without executing. A syntax check does not validate scientific results.
  rfiles <- c(list.files(file.path(.workflow_root, "R"), "[.]R$", full.names = TRUE),
    list.files(file.path(.workflow_root, "scripts"), "[.]R$", full.names = TRUE))
  parse_errors <- vapply(rfiles, function(f) tryCatch({parse(f); ""},
    error = function(e) conditionMessage(e)), "")
  ok <- !length(missing_packages) && !length(missing_files) && !any(nzchar(parse_errors))
  cat("Project:", spec$cfg$package, "\nR:", R.version.string,
    "\nSelected stages:", paste(stages, collapse = ", "), "\n")
  cat("Missing packages:", if (length(missing_packages)) paste(missing_packages, collapse = ", ") else "none", "\n")
  cat("Missing required files:", length(missing_files), "\n")
  if (length(missing_files)) print(missing_files)
  if (any(nzchar(parse_errors))) print(parse_errors[nzchar(parse_errors)])
  cat("Parse checks:", length(rfiles), "R files\n")
  cat("Preflight:", if (ok) "PASS (presence and syntax only)" else "FAIL", "\n")
  invisible(list(ok = ok, missing_packages = missing_packages, missing_files = missing_files,
    parse_errors = parse_errors[nzchar(parse_errors)]))
}

.workflow_child <- function(script, arguments = character(), label = "stage") {
  spec <- .workflow_spec()
  rs <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  oldwd <- getwd()
  envnames <- c("R_LIBS", "TZ", "TW_SKIP_REPORTS", "TP_MAX_PAIRS", "TW_FM_CACHE")
  oldenv <- Sys.getenv(envnames, unset = NA_character_)
  on.exit({
    setwd(oldwd)
    for (i in seq_along(envnames)) {
      if (is.na(oldenv[i])) Sys.unsetenv(envnames[i]) else
        do.call(Sys.setenv, setNames(list(oldenv[i]), envnames[i]))
    }
  }, add = TRUE)
  setwd(.workflow_root)
  # Child sessions use the libraries selected in RStudio and avoid startup profiles.
  Sys.setenv(R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep), TZ = "Asia/Thimphu",
    TW_SKIP_REPORTS = "true")
  Sys.unsetenv(c("TP_MAX_PAIRS", "TW_FM_CACHE"))
  dir.create("logs", showWarnings = FALSE)
  stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  log <- tempfile(paste0("rstudio_", stamp, "_", label, "_"), tmpdir = "logs", fileext = ".log")
  cat("Running", script, "\nLog:", log, "\n")
  status <- system2(rs, c("--vanilla", shQuote(script), vapply(arguments, shQuote, "")),
    stdout = log, stderr = log)
  cat(paste(tail(readLines(log, warn = FALSE), 25), collapse = "\n"), "\n")
  if (status != 0) stop("Child R session failed (", status, "). Full log: ", log)
  invisible(log)
}

run_project <- function(stages = NULL) {
  spec <- .workflow_spec()
  if (is.null(stages)) stages <- spec$defaults
  result <- check_project(stages)
  if (!result$ok) stop("Resolve the preflight failures before running analysis.")
  message("Existing outputs and proposed field forms for the selected stages will be replaced. Keep completed forms outside generated folders.")
  logs <- lapply(stages, function(id) .workflow_child(file.path("scripts", spec$stages[[id]]), label = id))
  names(logs) <- stages
  message("Selected child processes returned success. Read their logs and data-health reports before accepting results.")
  invisible(logs)
}

run_lesson <- function(id = "list") {
  if (length(id) != 1L || !is.character(id)) stop("Supply one lesson ID or 'list'.")
  files <- list.files(file.path(.workflow_root, "r_studio_run"),
    pattern = "^lesson-[0-9]+-[0-9]+[.]R$")
  ids <- sub("^lesson-([0-9]+)-([0-9]+)[.]R$", "\\1.\\2", files)
  if (identical(id, "list")) {
    titles <- vapply(files, function(file)
      readLines(file.path(.workflow_root, "r_studio_run", file), n = 1L, warn = FALSE), "")
    cat(paste(sub("^# ", "", titles), collapse = "\n"), "\n")
    return(invisible(ids))
  }
  if (is.na(id) || !id %in% ids) stop("Unknown lesson: ", id)
  .workflow_child(file.path("r_studio_run", files[match(id, ids)]), label = paste0("lesson_", id))
}
