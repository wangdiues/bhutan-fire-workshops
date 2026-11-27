# Track settlement-related change | outputs/03-growth
# Open the extracted .Rproj, then select one numbered block and press Ctrl+Enter.
# All values come from the workshop files. Block 10 can rerun the original analysis.

# Block 01: Check the packages ----
# Make sure R can open the packages this practical uses.
packages <- c("jsonlite", "terra")
ready <- vapply(packages, requireNamespace, logical(1), quietly = TRUE)
if (!all(ready)) {
  stop("Run 01_Install_Workshop_Packages.R first. Missing: ",
    paste(packages[!ready], collapse = ", "), call. = FALSE)
}
message("Packages are ready.")

# Block 02: Link the project folder ----
# Use the open RStudio project as the starting folder.
# The combined project contains both workshop folders.
# The single-workshop project is also supported.
workshop_folder <- "."
if (file.exists("Bhutan_Forest_Fire_Workshops.Rproj")) {
  workshop_folder <- "thimphu_WUI"
}
settings_file <- file.path(workshop_folder, "config", "settings.json")
if (!file.exists(settings_file) ||
    !identical(jsonlite::read_json(settings_file)$package, "thimphu_WUI")) {
  stop("Open the workshop .Rproj from the fully extracted ZIP first.", call. = FALSE)
}
message("Workshop folder: ", normalizePath(workshop_folder, winslash = "/"))

# Block 03: Link the data files ----
# Define every file path used by this practical, relative to the project.
# Annual built-up and WUI proxy area with observation counts.
annual_file <- file.path(workshop_folder, "data/derived/wui_annual_dynamic_world.csv")

# Reviewed majority-class change map for the early and late periods.
change_file <- file.path(workshop_folder, "data/derived/wui_change_2017_19_to_2023_25_50m.tif")

required_files <- c(annual_file, change_file)

# Block 04: Check the files ----
# Confirm the project contains every file listed above before reading it.
missing_files <- required_files[!file.exists(required_files)]
if (length(missing_files) > 0) {
  stop("Missing data files:\n", paste(missing_files, collapse = "\n"), call. = FALSE)
}
message("All required data files are available.")

# Block 05: Import the data ----
# Open the reviewed project files using the paths from Block 03.
annual <- read.csv(annual_file)
change_map <- terra::rast(change_file)

# Block 06: Examine the data ----
# Look at the structure or the first values before interpreting the result.
print(annual[, c("year", "partial", "wui_km2", "mean_valid_obs")], row.names = FALSE)

# Block 07: Work through the result ----
# Summarise and interpret the reviewed analysis with a small calculation.
results <- annual[!annual$partial, c("year", "wui_km2", "mean_valid_obs")]
pairs <- utils::combn(seq_len(nrow(results)), 2)
area_change <- results$wui_km2[pairs[2, ]] - results$wui_km2[pairs[1, ]]
years_between <- results$year[pairs[2, ]] - results$year[pairs[1, ]]
cat("Median pairwise slope (km2/year):", median(area_change / years_between), "\n")

# Block 08: Visualise the result ----
# Use the plot to connect the numbers to the map or chart.
plot(results$year, results$wui_km2, type = "b", col = "#176451",
  xlab = "Complete year", ylab = "WUI settlement proxy (km2)")
terra::plot(change_map, main = "Reviewed early-to-late WUI change")

# Block 09: Export your table ----
# Save a CSV, a simple spreadsheet-compatible file, for notes or discussion.
answer_folder <- file.path(workshop_folder, "teaching_outputs")
dir.create(answer_folder, showWarnings = FALSE)
answer_file <- file.path(answer_folder, "03-growth.csv")
write.csv(results, answer_file, row.names = FALSE)
message("Saved: ", answer_file)

# Block 10: Replay the original analysis (optional) ----
# Run the original scientific stage, with its own data and package checks, from a separate copy of the project.
# Change this to TRUE only in a separate copy of the project.
# Rebuild writes to that copy's analysis outputs and can take substantial time.
rebuild <- FALSE
if (rebuild) {
  local({
    source(file.path(workshop_folder, "START_HERE.R"), local = TRUE, chdir = TRUE)
    run_project(c("04"))
  })
}
