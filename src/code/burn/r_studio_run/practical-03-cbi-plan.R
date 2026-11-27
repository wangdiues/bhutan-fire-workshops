# Design field checks for spectral change | outputs/03-cbi-plan
# Open the extracted .Rproj, then select one numbered block and press Ctrl+Enter.
# All values come from the workshop files. Block 10 can rerun the original analysis.

# Block 01: Check the packages ----
# Make sure R can open the packages this practical uses.
packages <- c("jsonlite")
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
# Planned calibration plots, strata and primary or reserve roles.
calibration_file <- file.path(workshop_folder, "data/derived/field_plan/A_calibration_plots.csv")

# Independent accuracy design with strata, area and inclusion probability.
accuracy_file <- file.path(workshop_folder, "data/derived/field_plan/B_accuracy_sample.csv")

# Reviewed sample counts for both designs.
summary_file <- file.path(workshop_folder, "data/derived/results_field_plan.json")

required_files <- c(calibration_file, accuracy_file, summary_file)

# Block 04: Check the files ----
# Confirm the project contains every file listed above before reading it.
missing_files <- required_files[!file.exists(required_files)]
if (length(missing_files) > 0) {
  stop("Missing data files:\n", paste(missing_files, collapse = "\n"), call. = FALSE)
}
message("All required data files are available.")

# Block 05: Import the data ----
# Open the reviewed project files using the paths from Block 03.
calibration <- read.csv(calibration_file)
accuracy <- read.csv(accuracy_file)
review <- jsonlite::read_json(summary_file, simplifyVector = TRUE)

# Block 06: Examine the data ----
# Look at the structure or the first values before interpreting the result.
print(with(calibration, table(stratum, role)))
print(table(accuracy$stratum))

# Block 07: Work through the result ----
# Summarise and interpret the reviewed analysis with a small calculation.
results <- unique(accuracy[, c("stratum", "inclusion_probability", "stratum_area_ha")])
results$design_weight <- 1 / results$inclusion_probability
print(results, row.names = FALSE)
print(review[c("n_A", "n_A_primary", "n_A_reserve", "n_B")])

# Block 08: Visualise the result ----
# Use the plot to connect the numbers to the map or chart.
barplot(c(Calibration = nrow(calibration), Accuracy = nrow(accuracy)),
  ylab = "Planned points", col = c("#176451", "#a14b27"), main = "Two field samples")

# Block 09: Export your table ----
# Save a CSV, a simple spreadsheet-compatible file, for notes or discussion.
answer_folder <- file.path(workshop_folder, "teaching_outputs")
dir.create(answer_folder, showWarnings = FALSE)
answer_file <- file.path(answer_folder, "03-cbi-plan.csv")
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
