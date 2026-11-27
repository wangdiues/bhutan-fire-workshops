# Lesson 2.4 | Find large wildland patches and measure distance to them
# Run the setup first, then select the calculation or click Source for the whole file.
# Numerical examples describe the workshop dataset and settings.

# Load project helpers and the packaged inputs used below.
source("r_studio_run/00_setup.R", local = TRUE)

g <- grid50()
vs <- rast(tw("data/inputs/vegetation_shares_50m.tif")) / 100
veg <- mask(vs[["wc_tree"]] + vs[["wc_shrub"]] + vs[["wc_grass"]], vs[["ftm_forest_scrub"]])
core <- ifel(veg >= CFG$patch_vegetation_share, 1, NA)              # cells at least 75% vegetated
pid <- patches(core, directions = 8, zeroAsNA = TRUE)                # join touching cells (8 neighbours) into patches
pa <- freq(pid); pa$km2 <- pa$count * km2                            # size of every patch
say("Patches found: %s | largest %.0f km2 | patches >= 5 km2: %d | patches < 0.5 km2: %s",
    format(nrow(pa), big.mark = ","), max(pa$km2), sum(pa$km2 >= 5), format(sum(pa$km2 < 0.5), big.mark = ","))
big <- classify(pid, cbind(pa$value, ifelse(pa$km2 >= 5, 1, NA)))     # keep only patches of 5 km2 or more
dist <- distance(crop(big, window()))                                # metres from every cell to the nearest big patch
dv <- values(dist, mat = FALSE)
say("In the city window: cells inside a big patch %.0f%%, within 100 m %.0f%%, within 500 m %.0f%%, farther than 1 km %.0f%%",
    100 * mean(dv == 0, na.rm = TRUE), 100 * mean(dv > 0 & dv <= 100, na.rm = TRUE), 100 * mean(dv > 0 & dv <= 500, na.rm = TRUE), 100 * mean(dv > 1000, na.rm = TRUE))
f <- png_out("2.4_patch_distance"); plot(dist, main = "Distance (m) to a >= 5 km2 wildland patch"); dev.off(); say("Picture: %s", f)

