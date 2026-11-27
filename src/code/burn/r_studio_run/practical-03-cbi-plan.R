# CBI calibration and independent accuracy | outputs/03-cbi-plan
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
if (rebuild) run_project(c("04"))

# ---- Compare sample purposes using the real design tables ----
calibration <- read.csv("data/derived/field_plan/A_calibration_plots.csv")
accuracy <- read.csv("data/derived/field_plan/B_accuracy_sample.csv")
print(with(calibration, table(stratum, role)))
print(table(accuracy$stratum))

# ---- Examine the independent accuracy sample's design weights ----
# The accuracy sample has an explicit probability of selection in each stratum.
# A small inclusion probability gives an observation more design weight.
design <- unique(accuracy[c("stratum", "inclusion_probability", "stratum_area_ha")])
stopifnot(all(design$inclusion_probability > 0))
design$design_weight <- 1 / design$inclusion_probability
print(design, row.names = FALSE)
# Calibration relates field scores to spectral metrics. Independent field
# reference labels are needed to estimate accuracy and adjusted mapped area.
