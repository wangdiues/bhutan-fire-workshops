# Satellite detection and spectral change | outputs/01-severity
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
if (rebuild) run_project(c("02"))

# ---- Compare detections by sensor using the real incident-sensor table ----
pairs <- read.csv("data/derived/incident_sensor_metrics.csv")
stopifnot(nrow(pairs) > 0, "detected" %in% names(pairs))
print(with(pairs, table(sensor, detected, useNA = "ifany")))
print(aggregate(detected ~ sensor, pairs, mean))

# ---- Compare rule selection and independent evaluation ----
result <- jsonlite::read_json("data/derived/results_severity.json", simplifyVector = TRUE)
print(result[c("incidents_imaged", "pairs", "incidents_mapped", "rule_q",
  "rule_min_ha", "placebo_selection", "placebo_heldout", "placebo_heldout_ci")])
# The reference ring estimates background change. Held-out zones and independent
# thermal evidence test the detection rule. Classes represent provisional spectral change.
