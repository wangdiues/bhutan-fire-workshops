# Interpret fire-management screening | outputs/05-fire-mgmt
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
# Counts and length after each fire-line constraint.
line_file <- file.path(workshop_folder, "data/derived/fire_mgmt/fire_line_exclusion_funnel.csv")

# Remaining cells and hectares after each area constraint.
area_file <- file.path(workshop_folder, "data/derived/fire_mgmt/rx_eligibility_funnel.csv")

# How selected sites respond when ranking weights change.
sensitivity_file <- file.path(workshop_folder, "data/derived/fire_mgmt/sensitivity_rx_sites.csv")

# Reviewed local map of suitability categories.
map_file <- file.path(workshop_folder, "data/derived/fire_mgmt/rx_suitability_50m.tif")

required_files <- c(line_file, area_file, sensitivity_file, map_file)

# Block 04: Check the files ----
# Confirm the project contains every file listed above before reading it.
missing_files <- required_files[!file.exists(required_files)]
if (length(missing_files) > 0) {
  stop("Missing data files:\n", paste(missing_files, collapse = "\n"), call. = FALSE)
}
message("All required data files are available.")

# Block 05: Import the data ----
# Open the reviewed project files using the paths from Block 03.
lines <- read.csv(line_file)
areas <- read.csv(area_file)
weights <- read.csv(sensitivity_file)
suitability <- terra::rast(map_file)

# Block 06: Examine the data ----
# Look at the structure or the first values before interpreting the result.
print(lines[, c("rule", "cumulative_km")], row.names = FALSE)
print(weights)

# Block 07: Work through the result ----
# Summarise and interpret the reviewed analysis with a small calculation.
results <- areas[, c("rule", "cumulative_ha")]
previous <- c(NA, head(results$cumulative_ha, -1))
results$removed_ha <- previous - results$cumulative_ha
print(results, row.names = FALSE)

# Block 08: Visualise the result ----
# Use the plot to connect the numbers to the map or chart.
terra::plot(suitability, main = "Reviewed management screening classes")

# Block 09: Export your table ----
# Save a CSV, a simple spreadsheet-compatible file, for notes or discussion.
answer_folder <- file.path(workshop_folder, "teaching_outputs")
dir.create(answer_folder, showWarnings = FALSE)
answer_file <- file.path(answer_folder, "05-fire-mgmt.csv")
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
    run_project(c("15", "16"))
  })
}
