# Lesson 4.1 | A spectral trajectory by hand (an older fire with 4 years of follow-up)
# Run the setup first, then select the calculation or click Source for the whole file.
# Numerical examples describe the workshop dataset and settings.

# Load project helpers and the packaged inputs used below.
# Block 01: Open the shared lesson setup ----
lesson_setup <- "thimphu_paro_burn_severity/r_studio_run/00_setup.R"
if (!file.exists(lesson_setup)) lesson_setup <- "r_studio_run/00_setup.R"
source(lesson_setup, local = TRUE)

# Block 02: Run the short exercise and read its output ----

pat <- st_read(file.path(DER, "burn_severity_paro_thimphu.gpkg"), "burned_patches_selected", quiet = TRUE)
ip <- st_read(file.path(DER, "burn_severity_paro_thimphu.gpkg"), "incident_points", quiet = TRUE)
e <- training_example("trajectory_event"); pe <- pat[pat$event_id == e, ]; pt <- ip[ip$event_id == e, ]
fd <- as.Date(pe$fire_date[1]); y <- as.integer(format(fd, "%Y")); t0 <- if (as.integer(format(fd, "%m")) <= 6) y else y + 1
ring <- suppressWarnings(st_difference(st_difference(st_buffer(pt, 5000), st_buffer(pt, 2000)), st_union(st_buffer(pat, 100))))
yrs <- 2016:2025
nb <- rast(lapply(yrs, function(yy) { r <- rast(tp("data/raw/landsat_annual_nbr", sprintf("landsat_nbr_%d.tif", yy))); v <- r[["nbr_x10000"]] / 1e4; v[r[["valid_observations"]] < 1] <- NA; v }))
pv <- vapply(1:nlyr(nb), function(i) global(mask(crop(nb[[i]], vect(pe)), vect(st_union(pe))), "mean", na.rm = TRUE)[1, 1], 0)
rv <- vapply(1:nlyr(nb), function(i) global(mask(crop(nb[[i]], vect(ring)), vect(ring)), fun = function(x) median(x, na.rm = TRUE))[1, 1], 0)
d <- data.frame(year = yrs, t = yrs - t0, patch_nbr = round(pv, 3), ring_nbr = round(rv, 3)); d$diff <- round(d$patch_nbr - d$ring_nbr, 3)
d$rel <- round(d$diff - d$diff[d$year == t0 - 1], 3)
say("Fire %s on %s (%.0f ha mapped); year 0 = %d (first annual composite mostly after the fire)", e, fd, sum(pe$area_ha), t0)
print(d, row.names = FALSE)
say("rel = (patch - ring) minus the same difference in the last year before the fire; negative = darker / less vegetated than the surroundings.")
say("(This lesson uses the zonal mean/median of 30 m pixels; step 03 uses exact area-weighted extraction, so numbers can differ slightly.)")

