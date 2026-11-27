# Read the signal in the years after fire | outputs/02-recovery
# Open the extracted .Rproj, then select one numbered block and press Ctrl+Enter.
# All values come from the workshop files. Block 10 can rerun the original analysis.

# Block 01: Check the packages ----
# Make sure R can open the packages this practical uses.
packages <- c("jsonlite", "openxlsx")
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
# Annual patch and ring contrasts for individual mapped fires.
table_file <- file.path(workshop_folder, "outputs/02-recovery/process_data/02_incident_year_trajectory.xlsx")

# Reviewed model estimates, intervals and coverage counts.
model_file <- file.path(workshop_folder, "data/derived/results_recovery.json")

required_files <- c(table_file, model_file)

# Block 04: Check the files ----
# Confirm the project contains every file listed above before reading it.
missing_files <- required_files[!file.exists(required_files)]
if (length(missing_files) > 0) {
  stop("Missing data files:\n", paste(missing_files, collapse = "\n"), call. = FALSE)
}
message("All required data files are available.")

# Block 05: Import the data ----
# Open the reviewed project files using the paths from Block 03.
trajectory <- openxlsx::read.xlsx(table_file)
review <- jsonlite::read_json(model_file, simplifyVector = TRUE)

# Block 06: Examine the data ----
# Look at the structure or the first values before interpreting the result.
print(table(trajectory$t))
print(review$followup, row.names = FALSE)

# Block 07: Work through the result ----
# Summarise and interpret the reviewed analysis with a small calculation.
results <- review$emm[, c("t", "emmean", "lower.CL", "upper.CL")]
results <- results[order(results$t), ]
print(results, row.names = FALSE)
cat("Incidents in the model:", review$n_incidents, "\n")

# Block 08: Visualise the result ----
# Use the plot to connect the numbers to the map or chart.
plot(results$t, results$emmean, type = "b", xlab = "Years since fire",
  ylab = "Adjusted NBR", ylim = range(results$lower.CL, results$upper.CL))
segments(results$t, results$lower.CL, results$t, results$upper.CL)
abline(h = 0, lty = 2)

# Block 09: Export your table ----
# Save a CSV, a simple spreadsheet-compatible file, for notes or discussion.
answer_folder <- file.path(workshop_folder, "teaching_outputs")
dir.create(answer_folder, showWarnings = FALSE)
answer_file <- file.path(answer_folder, "02-recovery.csv")
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
    run_project(c("03"))
  })
}
