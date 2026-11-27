# Lesson 1.1 | Look at the packaged data
# Run the setup first, then select the calculation or click Source for the whole file.
# Numerical examples describe the workshop dataset and settings.

# Load project helpers and the packaged inputs used below.
source("r_studio_run/00_setup.R", local = TRUE)
EXAMPLE <- training_example("mapping_event")
SENSOR <- training_example("mapping_sensor")
KEY <- paste(EXAMPLE, SENSOR, sep = "_")
inc <- read.csv(tp("data/inputs/dofps_incidents_paro_thimphu.csv"))

hr("Settings (config/settings.json, section 'severity')")
say("Ring %d-%d m | search radius %d m | NDVI mask < %.1f | shadow mask cos(i) < %.2f | RBR breaks %d / %d | main windows %s",
    SV$reference_ring_m[1], SV$reference_ring_m[2], SV$search_radius_m, SV$min_pre_ndvi_vegetated, SV$min_cos_illumination,
    SV$rbr_low_moderate, SV$rbr_moderate_high, paste(WIN$main, collapse = " vs "))
hr("DoFPS fire records")
say("Rows: %d | inside the study area with valid coordinates and dates: %d", nrow(inc), sum(inc$in_study_area))
i2 <- inc[inc$in_study_area, ]; print(table(dzongkhag = i2$dzongkhag, year = substr(i2$start_date_local, 1, 4)))
print(summary(i2$reported_area_ha))
hr("Satellite composites")
inv <- read.csv(tp("data/inputs/event_imagery_inventory.csv")); print(table(status = inv$status, sensor = inv$sensor))
say("v1.0 adjacent-window files (data/raw/events): %d .tif", length(list.files(EV, "[.]tif$")))
say("v1.1 season-matched files (data/raw/events_seasonal): %d .tif", length(list.files(ES, "[.]tif$")))
say("Annual Landsat NBR (data/raw/landsat_annual_nbr): %d years", length(list.files(tp("data/raw/landsat_annual_nbr"), "[.]tif$")))
hr("One season-matched composite")
r <- rast(file.path(ES, paste0(KEY, ".tif"))); m <- fromJSON(file.path(ES, paste0(KEY, ".json")))
say("%s: %d bands, %d x %d pixels of %g m", basename(sources(r)), nlyr(r), nrow(r), ncol(r), res(r)[1])
for (t in names(m$windows)) say("  window %-4s %s to %s  %2d images", t, m$windows[[t]]$start, m$windows[[t]]$end_exclusive, m$windows[[t]]$n_images)
hr("Independent thermal evidence")
say("FIRMS points: %d | MODIS MCD64A1 burned pixels: %d", nrow(read.csv(file.path(VD, "firms_points.csv"))), nrow(read.csv(file.path(VD, "mcd64a1_burned_pixels.csv"))))

