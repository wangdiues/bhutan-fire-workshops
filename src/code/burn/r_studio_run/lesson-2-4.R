# Lesson 2.4 | Detect the burned patch: candidates, patches, size, search zone, growth
# Run the setup first, then select the calculation or click Source for the whole file.
# Numerical examples describe the workshop dataset and settings.

# Load project helpers and the packaged inputs used below.
source("r_studio_run/00_setup.R", local = TRUE)
EXAMPLE <- training_example("mapping_event")
SENSOR <- training_example("mapping_sensor")
KEY <- paste(EXAMPLE, SENSOR, sep = "_")

P <- example(); res <- RES(); q <- res$rule_q; mh <- res$rule_min_ha
D0 <- detect(P, q, mh, grow = FALSE); D1 <- detect(P, q, mh, grow = TRUE)
cand <- P$usable & P$V$dnbr_c >= 0.1 & P$V$rbr >= D0$thr
say("Rule chosen in step 02: ring percentile %.1f, minimum patch %.2f ha", 100 * q, mh)
say("1. Threshold = %.1f percentile of ring RBR = %.0f", 100 * q, D0$thr)
say("2. Candidate pixels (dNBR_c >= 0.100 and RBR >= %.0f): %s", D0$thr, format(sum(cand), big.mark = ","))
say("3. Patches (8-connected groups): %s; of these >= %.2f ha (%d pixels): %d", format(length(unique(na.omit(D0$pv))), big.mark = ","), mh, max(2, ceiling(mh / P$px_ha)), length(D0$big))
say("4. Large patches touching the 500 m search zone: %d -> %.1f ha", length(D0$keep), sum(D0$inpatch) * P$px_ha)
say("5. After growth into connected pixels above the ring 95th percentile (RBR %.0f): %.1f ha", unname(quantile(P$V$rbr[P$ring], SV$grow_quantile)), sum(D1$inpatch) * P$px_ha)
cl <- cut(P$V$rbr[D1$inpatch], c(-Inf, SV$rbr_low_moderate, SV$rbr_moderate_high, Inf), labels = SEV_SHORT[-1], right = FALSE)
say("6. Spectral-change classes (ha): %s", paste(names(table(cl)), round(as.numeric(table(cl)) * P$px_ha, 1), collapse = ", "))
M <- read.csv(file.path(DER, "incident_sensor_metrics.csv"))
say("   Reported area: %.1f ha (step 02 mapped %.2f ha for this pair)", P$ev$reported_area_ha, M$mapped_area_ha[M$event_id == EXAMPLE & M$sensor == SENSOR])
sev <- rep(NA_integer_, nrow(P$V)); sev[P$usable] <- 0L; sev[D1$inpatch] <- as.integer(cl)
f <- png_out("2.4_detection"); par(mfrow = c(1, 3))
plot(setValues(P$g, ifelse(cand, 1, NA)), main = "candidate pixels", col = "black", legend = FALSE); plot(P$pt, add = TRUE, pch = 3, cex = 2, col = "red")
plot(setValues(P$g, ifelse(D0$inpatch, 1, NA)), main = "detected patch (before growth)", col = "darkred", legend = FALSE); plot(P$pt, add = TRUE, pch = 3, cex = 2)
plot(setValues(P$g, sev), main = "classes after growth", col = unname(SEV_COLS), type = "classes", levels = SEV_SHORT, legend = "bottomright"); plot(P$pt, add = TRUE, pch = 3, cex = 2)
dev.off(); say("Picture: %s", f)

