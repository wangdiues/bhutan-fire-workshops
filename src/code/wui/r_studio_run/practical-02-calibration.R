# Association with recorded fire | outputs/02-calibration
# Open the workshop .Rproj and use the actual contents of the participant ZIP.
# Run the setup, then the section blocks with Ctrl+Enter. Source runs the whole file.

# ---- Choose whether to rebuild the result ----
# FALSE reads the packaged reviewed output. Set TRUE in a working copy to rerun
# the existing analysis stages and replace their generated files.
rebuild <- FALSE
if (!file.exists("START_HERE.R")) {
  stop("Open the .Rproj inside the extracted workshop project.", call. = FALSE)
}
source("START_HERE.R", local = TRUE)
if (rebuild) run_project(c("03"))

# ---- Read the selected rule and compare evaluation designs ----
result <- jsonlite::read_json("data/derived/results_calibration.json", simplifyVector = TRUE)
print(result$selected)
print(result[c("J_baseline", "J_selected", "cv_J", "boot_ci")])
# Youden J = sensitivity + specificity - 1. The selected score is in-sample.
# Leave-one-gewog-out evaluation asks whether the result transfers spatially.
rules <- read.csv("data/derived/calibration_all_rules.csv", check.names = FALSE)
cat("Candidate rules:", nrow(rules), "\n")
print(head(rules, 6))
# Compare baseline and selected area. Recorded proximity captures an association.
print(result[c("baseline_wui_km2", "selected_wui_km2", "exposed_share_buildings")])
