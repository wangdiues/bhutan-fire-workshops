# Lesson 5.1 | Exposure of buildings and people
# Run the setup first, then select the calculation or click Source for the whole file.
# Numerical examples describe the workshop dataset and settings.

# Load project helpers and the packaged inputs used below.
# Block 01: Open the shared lesson setup ----
lesson_setup <- "thimphu_WUI/r_studio_run/00_setup.R"
if (!file.exists(lesson_setup)) lesson_setup <- "r_studio_run/00_setup.R"
source(lesson_setup, local = TRUE)

# Block 02: Run the short exercise and read its output ----

b <- st_drop_geometry(st_read(tw("data/derived/wui_thimphu.gpkg"), "buildings", quiet = TRUE))
say("Buildings: %s | in WUI: %s (%.1f%%)", format(nrow(b), big.mark = ","), format(sum(b$in_wui), big.mark = ","), 100 * mean(b$in_wui))
print(with(b[b$in_wui, ], table(`fire within 1 km` = fire_within_1km, `high susceptibility` = high_susceptibility, useNA = "ifany")))
say("WUI buildings more than 1 h walk from a road: %d", sum(b$in_wui & b$walk_h > 1, na.rm = TRUE))
g <- grid50(); inside <- values(g, mat = FALSE) %in% 2
pop <- values(rast(tw("data/inputs/population_2020_50m.tif")), mat = FALSE); pop[is.na(pop)] <- 0
cl <- values(rast(tw("data/derived/wui_class_calibrated_50m.tif")), mat = FALSE)
say("Modelled people (WorldPop 2020): Thimphu %.0f | in WUI %.0f", sum(pop[inside]), sum(pop[inside & cl %in% 1:2]))

