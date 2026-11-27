# Structural WUI and sensitivity | outputs/01-sensitivity
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

# ---- Compare density and vegetation choices ----
# The reference WUI map combines building density, vegetation share and distance
# to a vegetation patch. The sensitivity workbook varies one choice at a time.
baseline <- jsonlite::read_json("data/derived/results_layers.json", simplifyVector = TRUE)
print(baseline[c("buildings_thimphu", "baseline_wui_km2", "baseline_building_share")])
sensitivity <- openxlsx::read.xlsx("outputs/01-sensitivity/process_data/04_sensitivity_one_at_a_time.xlsx")
print(head(sensitivity, 12))

# ---- Read the two building sources ----
# Compare results with the same input settings to isolate the effect of source.
print(baseline[c("wui_buildings_ob", "wui_buildings_agency", "veg_agreement")])
# Which choice changes the result most? Record the rule, units and study area.
# The structural benchmark is a raster adaptation. Field accuracy is unresolved.
