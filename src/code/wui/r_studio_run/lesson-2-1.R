# Lesson 2.1 | Count buildings in each 50 m cell
# Run the setup first, then select the calculation or click Source for the whole file.
# Numerical examples describe the workshop dataset and settings.

# Load project helpers and the packaged inputs used below.
source("r_studio_run/00_setup.R", local = TRUE)

g <- grid50()
ob <- st_read(tw("data/inputs/buildings.gpkg"), "open_buildings_v3", quiet = TRUE)
ob <- ob[ob$confidence >= CFG$buildings$confidence_min, ]            # keep reliable footprints only
cell <- cellFromXY(g, st_coordinates(ob))                            # which cell is each building centre in?
n <- tabulate(cell[!is.na(cell)], ncell(g))                          # how many buildings per cell
bcount <- rast(g); values(bcount) <- n; bcount <- mask(bcount, g)    # put the counts back on the map
say("Buildings placed on the grid: %s", format(sum(n), big.mark = ","))
say("Cells with at least one building: %s (%.1f km2)", format(sum(n > 0), big.mark = ","), sum(n > 0) * km2)
say("Most buildings in one 50 m cell: %d", max(n))
print(table(cut(n[n > 0], c(0, 1, 2, 5, 10, Inf), labels = c("1", "2", "3-5", "6-10", ">10"))))
f <- png_out("2.1_building_count"); plot(crop(bcount, window()), main = "Buildings per 50 m cell (Thimphu city window)", col = hcl.colors(20, "YlOrRd", rev = TRUE)); dev.off()
say("Picture: %s", f)

