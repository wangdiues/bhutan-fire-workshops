# Lesson 1.1 | Look at the packaged data
# Run the setup first, then select the calculation or click Source for the whole file.
# Numerical examples describe the workshop dataset and settings.

# Load project helpers and the packaged inputs used below.
source("r_studio_run/00_setup.R", local = TRUE)

hr("Settings (config/settings.json)")
say("Map projection: %s | grid cell: %d m | baseline rule: D=%.2f V=%d P=%d R=%d A=%g veg=%s",
    CRS, RES, CFG$baseline$D, CFG$baseline$V, CFG$baseline$P, CFG$baseline$R, CFG$baseline$A, CFG$baseline$veg)
hr("The 50 m grid")
g <- grid50(); print(g)
tab <- table(values(g, mat = FALSE))
say("Cells with value 2 (Thimphu): %s = %.0f km2 | value 1 (5 km buffer): %s", format(tab[["2"]], big.mark = ","), tab[["2"]] * km2, format(tab[["1"]], big.mark = ","))
hr("Vector layers (GeoPackages)")
for (f in c("study_area", "buildings", "fire_evidence", "roads_osm")) {
  lay <- st_layers(tw("data/inputs", paste0(f, ".gpkg")))
  for (i in seq_along(lay$name)) say("%-14s %-18s %8s features", f, lay$name[i], format(lay$features[i], big.mark = ","))
}
hr("Raster layers (GeoTIFFs)")
for (f in c("vegetation_shares_50m.tif", "population_2020_50m.tif", "walk_time_h_50m.tif", "susceptibility_class_50m.tif", "dynamic_world/dw_2023_shares_50m.tif")) {
  r <- rast(tw("data/inputs", f)); say("%-38s layers: %s", f, paste(names(r), collapse = ", "))
}
hr("Buildings by confidence")
ob <- st_read(tw("data/inputs/buildings.gpkg"), "open_buildings_v3", quiet = TRUE)
print(summary(ob$confidence))
say("Footprints with confidence >= 0.70: %s of %s", format(sum(ob$confidence >= 0.70), big.mark = ","), format(nrow(ob), big.mark = ","))

