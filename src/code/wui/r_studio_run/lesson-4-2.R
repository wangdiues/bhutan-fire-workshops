# Lesson 4.2 | Choose the built-share threshold (kappa against 2023 footprints)
# Run the setup first, then select the calculation or click Source for the whole file.
# Numerical examples describe the workshop dataset and settings.

# Load project helpers and the packaged inputs used below.
source("r_studio_run/00_setup.R", local = TRUE)

g <- grid50(); inside <- which(values(g, mat = FALSE) %in% 2); w <- circle_w(g, 1000)
dom <- rast(file.path(LAY, "vegshare_ftm.tif"))
dense <- values(rast(file.path(LAY, "density_ob.tif"))[["r1000"]], mat = FALSE)[inside] > 20          # footprint "settled"
dw <- rast(tw("data/inputs/dynamic_world/dw_2023_shares_50m.tif"))
nb <- values(focal(mask(dw[["built"]] / 100, dom), w, fun = "mean", na.rm = TRUE), mat = FALSE)[inside]   # built share within 1 km
ok <- !is.na(nb) & !is.na(dense)
for (b in CFG$growth$built_share_grid) { k <- md_kappa(dense[ok], nb[ok] > b, c(FALSE, TRUE))
  say("threshold %4.1f%%: agreement %.3f  kappa %.3f", 100 * b, k[["agreement"]], k[["kappa"]]) }

