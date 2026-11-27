# Lesson 2.5 | Placebo zones around the example fire
# Run the setup first, then select the calculation or click Source for the whole file.
# Numerical examples describe the workshop dataset and settings.

# Load project helpers and the packaged inputs used below.
source("r_studio_run/00_setup.R", local = TRUE)
EXAMPLE <- training_example("mapping_event")
SENSOR <- training_example("mapping_sensor")
KEY <- paste(EXAMPLE, SENSOR, sep = "_")

P <- example(); res <- RES(); D0 <- detect(P, res$rule_q, res$rule_min_ha, grow = FALSE)
set.seed(1); ctr <- crds(P$pt); xy <- xyFromCell(P$g, seq_len(ncell(P$g)))
band <- function(b) as.numeric(if (is.matrix(PL$bands_m)) PL$bands_m[b, ] else PL$bands_m[[b]])
out <- do.call(rbind, lapply(1:3, function(b) do.call(rbind, lapply(seq_len(PL$zones_per_band), function(j) {
  a <- runif(1, 0, 2 * pi); r0 <- runif(1, band(b)[1], band(b)[2]); cx <- ctr[1] + r0 * cos(a); cy <- ctr[2] + r0 * sin(a)
  z <- which(sqrt((xy[, 1] - cx)^2 + (xy[, 2] - cy)^2) <= SV$search_radius_m)
  hit <- if (length(z) < 10 || any(D0$inpatch[z]) || mean(P$usable[z]) < 0.5) NA else any(unique(D0$pv[z][!is.na(D0$pv[z])]) %in% D0$big)
  data.frame(band = sprintf("%.1f-%.1f km", band(b)[1] / 1000, band(b)[2] / 1000), zone = j, distance_m = round(r0), detected = hit) }))))
print(out, row.names = FALSE)
say("Zones usable: %d of %d | 'fires' detected in empty zones: %d", sum(!is.na(out$detected)), nrow(out), sum(out$detected, na.rm = TRUE))
say("(Random positions here use a different seed from step 02, so the zones differ. Step 02 does this for every fire: %s held-out zones, rate %.1f%%.)",
    format(sum(res$placebo_bands$zones[res$placebo_bands$set == "Held-out zones"]), big.mark = ","), 100 * res$placebo_heldout)

