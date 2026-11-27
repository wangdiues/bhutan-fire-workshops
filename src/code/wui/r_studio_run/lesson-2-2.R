# Lesson 2.2 | Neighbourhood building density at three radii
# Run the setup first, then select the calculation or click Source for the whole file.
# Numerical examples describe the workshop dataset and settings.

# Load project helpers and the packaged inputs used below.
# Block 01: Open the shared lesson setup ----
lesson_setup <- "thimphu_WUI/r_studio_run/00_setup.R"
if (!file.exists(lesson_setup)) lesson_setup <- "r_studio_run/00_setup.R"
source(lesson_setup, local = TRUE)

# Block 02: Run the short exercise and read its output ----

g <- crop(grid50(), window())
bc <- crop(rast(file.path(LAY, "building_count_ob.tif")), g)
for (r in c(250, 500, 1000)) {
  w <- circle_w(g, r)                                               # circle of 1s: the neighbourhood
  area <- sum(w) * km2                                              # its area in km2
  d <- focal(bc, w, fun = "sum", na.rm = TRUE) / area               # buildings in circle / circle area
  say("R = %4d m: circle = %3d cells = %.3f km2 | median density where built-up: %.0f /km2 | cells above D=20: %.0f%%",
      r, sum(w), area, median(values(d)[values(bc) > 0], na.rm = TRUE), 100 * mean(values(d) > 20, na.rm = TRUE))
  if (r == 500) d500 <- d
}
say("Smallest whole number of buildings that exceeds D=20 in each circle: 250 m -> %d, 500 m -> %d, 1000 m -> %d",
    floor(20 * sum(circle_w(g, 250)) * km2) + 1, floor(20 * sum(circle_w(g, 500)) * km2) + 1, floor(20 * sum(circle_w(g, 1000)) * km2) + 1)
f <- png_out("2.2_density_500m"); plot(log10(d500 + 1), main = "log10(building density + 1), 500 m radius"); dev.off(); say("Picture: %s", f)

