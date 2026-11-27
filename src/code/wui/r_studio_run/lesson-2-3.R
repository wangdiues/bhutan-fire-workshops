# Lesson 2.3 | Wildland vegetation cover around each cell (three definitions)
# Run the setup first, then select the calculation or click Source for the whole file.
# Numerical examples describe the workshop dataset and settings.

# Load project helpers and the packaged inputs used below.
# Block 01: Open the shared lesson setup ----
lesson_setup <- "thimphu_WUI/r_studio_run/00_setup.R"
if (!file.exists(lesson_setup)) lesson_setup <- "r_studio_run/00_setup.R"
source(lesson_setup, local = TRUE)

# Block 02: Run the short exercise and read its output ----

g <- crop(grid50(), window())
vs <- crop(rast(tw("data/inputs/vegetation_shares_50m.tif")), g) / 100   # shares 0-1 in each 50 m cell
VEG <- list(ftm = vs[["ftm_forest_scrub"]], wc_woody = vs[["wc_tree"]] + vs[["wc_shrub"]],
            wc_woody_grass = vs[["wc_tree"]] + vs[["wc_shrub"]] + vs[["wc_grass"]])
w <- circle_w(g, 1000)
for (v in names(VEG)) {
  vp <- 100 * focal(VEG[[v]], w, fun = "mean", na.rm = TRUE)          # mean share in the circle, as %
  say("%-36s mean cell share %.0f%% | cells with >= 50%% cover within 1 km: %.0f%%", VEG_LABEL[[v]],
      100 * mean(values(VEG[[v]]), na.rm = TRUE), 100 * mean(values(vp) >= 50, na.rm = TRUE))
}
f <- png_out("2.3_vegetation"); par(mfrow = c(1, 3)); for (v in names(VEG)) plot(VEG[[v]], main = v, range = c(0, 1)); dev.off(); say("Picture: %s", f)

