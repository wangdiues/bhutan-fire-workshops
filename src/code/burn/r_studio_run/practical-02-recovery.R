# Post-fire spectral trajectories | outputs/02-recovery
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

# ---- Inspect years represented in the real incident-year workbook ----
trajectory <- openxlsx::read.xlsx("outputs/02-recovery/process_data/02_incident_year_trajectory.xlsx")
trajectory <- subset(trajectory, t >= -1 & t <= 4)
print(table(trajectory$t))
# rel is the patch-minus-reference-ring contrast after subtracting its baseline
# contrast. The number of reporting incidents changes with time.
average <- aggregate(rel ~ t, data = trajectory, FUN = mean)
plot(average$t, average$rel, type = "b", xlab = "Years since fire",
  ylab = "Mean baseline-adjusted NBR")
abline(h = 0, lty = 2)

# ---- Compare simple averages with the reviewed model summary ----
result <- jsonlite::read_json("data/derived/results_recovery.json", simplifyVector = TRUE)
print(result$emm)
# Which years have fewer incidents? Explain why spectral change is a proxy.
