# Lesson 2.1 | One fire: the before and after images
# Run the setup first, then select the calculation or click Source for the whole file.
# Numerical examples describe the workshop dataset and settings.

# Load project helpers and the packaged inputs used below.
source("r_studio_run/00_setup.R", local = TRUE)
EXAMPLE <- training_example("mapping_event")
SENSOR <- training_example("mapping_sensor")
KEY <- paste(EXAMPLE, SENSOR, sep = "_")

inc <- read.csv(tp("data/inputs/dofps_incidents_paro_thimphu.csv"), stringsAsFactors = FALSE)
ev <- inc[inc$event_id == EXAMPLE, ]
say("Example fire %s: %s gewog, %s, reported %s, %.1f ha, cause: %s", EXAMPLE, ev$gewog, ev$dzongkhag, ev$start_date_local, ev$reported_area_ha, ev$fire_cause)
P <- example()
say("Before (preM): %s to %s, %d images | After (p90): %s to %s, %d images", P$pre$start, P$pre$end, P$pre$n_images, P$post$start, P$post$end, P$post$n_images)
say("Grid: %d x %d pixels of %g m (%.2f ha each)", nrow(P$g), ncol(P$g), res(P$g)[1], P$px_ha)
near <- P$V$dist <= 500; ringv <- P$V$dist >= 2000 & P$V$dist <= 5000
say("Median NBR within 500 m of the report: before %.3f, after %.3f", median(P$V$pre[near], na.rm = TRUE), median(P$V$post[near], na.rm = TRUE))
say("Median NBR in the 2-5 km ring:         before %.3f, after %.3f", median(P$V$pre[ringv], na.rm = TRUE), median(P$V$post[ringv], na.rm = TRUE))
hr("NBR by hand for three example pixels (reflectance)")
ex <- data.frame(surface = c("dense forest", "grass slope", "freshly burned"), NIR = c(0.30, 0.22, 0.12), SWIR2 = c(0.08, 0.15, 0.20))
ex$NBR <- round((ex$NIR - ex$SWIR2) / (ex$NIR + ex$SWIR2), 3); print(ex, row.names = FALSE)
f <- png_out("2.1_before_after"); par(mfrow = c(1, 3))
plot(P$pre$nbr, main = "NBR before (same season, 2024)", range = c(-0.3, 0.7), fill_range = TRUE); plot(P$pt, add = TRUE, pch = 3, cex = 2)
plot(P$post$nbr, main = "NBR after (90 days after the fire)", range = c(-0.3, 0.7), fill_range = TRUE); plot(P$pt, add = TRUE, pch = 3, cex = 2)
plot(P$g - P$post$nbr, main = "dNBR = before - after", range = c(-0.3, 0.6), fill_range = TRUE); plot(P$pt, add = TRUE, pch = 3, cex = 2)
dev.off(); say("Picture: %s", f)

