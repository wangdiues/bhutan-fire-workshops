# Detect spectral change after a forest fire | outputs/01-severity
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
  workshop_folder <- "thimphu_paro_burn_severity"
}
settings_file <- file.path(workshop_folder, "config", "settings.json")
if (!file.exists(settings_file) ||
    !identical(jsonlite::read_json(settings_file)$package, "thimphu_paro_burn_severity")) {
  stop("Open the workshop .Rproj from the fully extracted ZIP first.", call. = FALSE)
}
message("Workshop folder: ", normalizePath(workshop_folder, winslash = "/"))

# Block 03: Link the data files ----
# Define every file path used by this practical, relative to the project.
# One row for each usable incident and sensor. Includes the detection flag and area.
pairs_file <- file.path(workshop_folder, "data/derived/incident_sensor_metrics.csv")

# Reviewed coverage, thresholds and independent evaluation results.
summary_file <- file.path(workshop_folder, "data/derived/results_severity.json")

# Chooses the same approved real event for every participant.
example_file <- file.path(workshop_folder, "config/training_examples.json")

# Read the approved example setting to find its matching classified image.
if (!file.exists(example_file)) stop("Missing: ", example_file, call. = FALSE)
example <- jsonlite::read_json(example_file)
map_name <- paste0(example$mapping_event, "_", example$mapping_sensor, "_severity.tif")
map_file <- file.path(workshop_folder, "data/derived/severity_rasters", map_name)

required_files <- c(pairs_file, summary_file, example_file, map_file)

# Block 04: Check the files ----
# Confirm the project contains every file listed above before reading it.
missing_files <- required_files[!file.exists(required_files)]
if (length(missing_files) > 0) {
  stop("Missing data files:\n", paste(missing_files, collapse = "\n"), call. = FALSE)
}
message("All required data files are available.")

# Block 05: Import the data ----
# Open the reviewed project files using the paths from Block 03.
pairs <- read.csv(pairs_file)
review <- jsonlite::read_json(summary_file, simplifyVector = TRUE)
change_map <- terra::rast(map_file)

# Block 06: Examine the data ----
# Look at the structure or the first values before interpreting the result.
print(with(pairs, table(sensor, detected, useNA = "ifany")))
print(review[c("rule_q", "rule_min_ha", "placebo_selection", "placebo_heldout")])

# Block 07: Work through the result ----
# Summarise and interpret the reviewed analysis with a small calculation.
results <- aggregate(detected ~ sensor, data = pairs, FUN = mean)
results$detection_pct <- 100 * results$detected
print(results[, c("sensor", "detection_pct")], row.names = FALSE)
print(review[c("pairs", "incidents_imaged", "incidents_mapped")])

# Block 08: Visualise the result ----
# Use the plot to connect the numbers to the map or chart.
terra::plot(change_map, main = "Reviewed spectral change for the training event")

# Block 09: Export your table ----
# Save a CSV, a simple spreadsheet-compatible file, for notes or discussion.
answer_folder <- file.path(workshop_folder, "teaching_outputs")
dir.create(answer_folder, showWarnings = FALSE)
answer_file <- file.path(answer_folder, "01-severity.csv")
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
    run_project(c("02"))
  })
}
