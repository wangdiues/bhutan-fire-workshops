# Lesson 5.2 | Gewog priority by ranks
# Run the setup first, then select the calculation or click Source for the whole file.
# Numerical examples describe the workshop dataset and settings.

# Load project helpers and the packaged inputs used below.
source("r_studio_run/00_setup.R", local = TRUE)

gt <- read.csv(tw("data/derived/exposure_by_gewog.csv"))
ind <- c("wui_buildings", "wui_fire_exposed_buildings", "wui_high_susceptibility_buildings", "wui_people")
rk <- sapply(ind, function(v) rank(-gt[[v]], ties.method = "average"))          # 1 = largest count
out <- data.frame(unit = gt$unit, gt[, ind], rk, score = rowMeans(rk)); names(out) <- c("unit", ind, paste0("rank_", c("bld", "fire", "sus", "ppl")), "score")
out$wui_people <- round(out$wui_people)
print(out[order(out$score), ], row.names = FALSE)

