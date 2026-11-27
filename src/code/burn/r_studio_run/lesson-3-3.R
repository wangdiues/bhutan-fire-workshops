# Lesson 3.3 | Landsat versus Sentinel-2 for the same fire (Jaccard overlap)
# Run the setup first, then select the calculation or click Source for the whole file.
# Numerical examples describe the workshop dataset and settings.

# Load project helpers and the packaged inputs used below.
source("r_studio_run/00_setup.R", local = TRUE)
EXAMPLE <- training_example("mapping_event")
SENSOR <- training_example("mapping_sensor")
KEY <- paste(EXAMPLE, SENSOR, sep = "_")

pa <- st_read(file.path(DER, "burn_severity_paro_thimphu.gpkg"), "burned_patches_all_sensors", quiet = TRUE)
e <- EXAMPLE; a <- st_union(pa[pa$event_id == e & pa$sensor == "landsat", ]); b <- st_union(pa[pa$event_id == e & pa$sensor == "sentinel", ])
i <- as.numeric(st_area(st_intersection(a, b))) / 1e4; u <- as.numeric(st_area(st_union(a, b))) / 1e4
say("%s: Landsat %.1f ha, Sentinel-2 %.1f ha, both %.1f ha, either %.1f ha -> Jaccard = %.1f / %.1f = %.2f",
    e, as.numeric(st_area(a)) / 1e4, as.numeric(st_area(b)) / 1e4, i, u, i, u, i / u)
res <- RES(); say("All fires: %d were imaged by both sensors and the sensors agree on detected / not detected for %.0f%% of them; among fires detected by both, the median Jaccard is %.2f.",
                  res$n_both, 100 * res$sensor_agreement, res$sensor_jaccard_median)

