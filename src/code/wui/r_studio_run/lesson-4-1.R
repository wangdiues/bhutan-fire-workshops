# Lesson 4.1 | Dynamic World: one year of land cover
# Run the setup first, then select the calculation or click Source for the whole file.
# Numerical examples describe the workshop dataset and settings.

# Load project helpers and the packaged inputs used below.
source("r_studio_run/00_setup.R", local = TRUE)

g <- grid50(); inside <- values(g, mat = FALSE) %in% 2
for (y in c(2017, 2023, 2025)) { r <- rast(tw("data/inputs/dynamic_world", sprintf("dw_%d_shares_50m.tif", y)))
  s <- sapply(c("trees", "grass", "shrub", "crops", "built", "bare", "water"), function(k) sum(values(r[[k]], mat = FALSE)[inside], na.rm = TRUE) / 100 * km2)
  say("%d: %s | mean cloud-free observations %.1f", y, paste(sprintf("%s %.0f", names(s), s), collapse = ", "), mean(values(r[["valid_obs"]], mat = FALSE)[inside], na.rm = TRUE)) }
say("(km2 of each class inside Thimphu)")

