# Exposure and the field kit | outputs/04-exposure
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
if (rebuild) run_project(c("05"))

# ---- Compare exposure indicators by gewog ----
exposure <- read.csv("data/derived/exposure_by_gewog.csv")
fields <- c("unit", "wui_buildings", "wui_people", "wui_fire_exposed_buildings",
  "wui_high_susceptibility_buildings", "wui_remote_buildings", "priority_rank")
print(exposure[order(exposure$priority_rank), fields], row.names = FALSE)

# ---- Interpret the estimated counts and field design ----
results <- jsonlite::read_json("data/derived/results_exposure.json", simplifyVector = TRUE)
print(results[c("wui_people", "remote_share", "field_points")])
# Population is a gridded estimate. Proximity, access and susceptibility provide
# separate evidence. Try ranking by one component and compare the order.
# Completed forms belong outside generated folders. Keep mapped labels with the analyst.
