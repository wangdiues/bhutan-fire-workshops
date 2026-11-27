# Lesson 3.4 | How much does mapped area depend on choices?
# Run the setup first, then select the calculation or click Source for the whole file.
# Numerical examples describe the workshop dataset and settings.

# Load project helpers and the packaged inputs used below.
source("r_studio_run/00_setup.R", local = TRUE)

r <- openxlsx::read.xlsx(tp("outputs/01-severity/process_data/10_provisional_area_range.xlsx"))
r$sum_ha <- round(r$sum_ha); print(r[, c("choice", "sum_ha")], row.names = FALSE)
res <- RES(); say("Atlas (unique) area %.0f ha: low %.0f, moderate %.0f, high %.0f, burned more than once %.0f | range across choices %.0f-%.0f ha",
                  res$atlas_total[["unique_ha"]], res$atlas_total[["low_ha"]], res$atlas_total[["moderate_ha"]], res$atlas_total[["high_ha"]], res$atlas_total[["repeat_ha"]], res$area_range_min, res$area_range_max)

