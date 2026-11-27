# Lesson 2.2 | Masks: non-vegetated and terrain shadow
# Run the setup first, then select the calculation or click Source for the whole file.
# Numerical examples describe the workshop dataset and settings.

# Load project helpers and the packaged inputs used below.
# Block 01: Open the shared lesson setup ----
lesson_setup <- "thimphu_paro_burn_severity/r_studio_run/00_setup.R"
if (!file.exists(lesson_setup)) lesson_setup <- "r_studio_run/00_setup.R"
source(lesson_setup, local = TRUE)

# Block 02: Run the short exercise and read its output ----
EXAMPLE <- training_example("mapping_event")
SENSOR <- training_example("mapping_sensor")
KEY <- paste(EXAMPLE, SENSOR, sep = "_")

P <- example(); V <- P$V; near <- V$dist <= 500
say("Sun at the middle of the post-fire window, 10:30 local time: elevation %.1f deg, azimuth %.0f deg", P$sun[["elevation"]], P$sun[["azimuth"]])
say("Whole image:  not vegetated before (NDVI < %.1f) %.0f%% | deep shadow (cos i < %.2f) %.0f%% | usable %.0f%%",
    SV$min_pre_ndvi_vegetated, 100 * mean(!(V$veg %in% TRUE)), SV$min_cos_illumination, 100 * mean(!(V$lit %in% TRUE)), 100 * mean(P$usable))
say("Within 500 m: not vegetated %.0f%% | deep shadow %.0f%% | usable %.0f%%", 100 * mean(!(V$veg[near] %in% TRUE)), 100 * mean(!(V$lit[near] %in% TRUE)), 100 * mean(P$usable[near]))
hr("cos(i) by hand: flat ground versus north- and south-facing 35 deg slopes")
sun <- P$sun; for (a in c(NA, 0, 180)) {
  ci <- if (is.na(a)) cos_incidence(0, 0, sun) else cos_incidence(35 * pi / 180, a * pi / 180, sun)
  say("  %-22s cos(i) = %.2f %s", if (is.na(a)) "flat" else if (a == 0) "35 deg, facing north" else "35 deg, facing south", ci, if (ci < SV$min_cos_illumination) "-> masked" else "") }
f <- png_out("2.2_masks"); par(mfrow = c(1, 2))
plot(P$cosi, main = "cos(i): sunlit (high) to shadow (low)"); plot(setValues(P$g, ifelse(P$usable, 1, 0)), main = "usable pixels (1)", col = c("grey80", "darkgreen")); dev.off()
say("Picture: %s", f)

