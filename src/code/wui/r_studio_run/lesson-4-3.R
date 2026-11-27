# Lesson 4.3 | Trend by hand: Theil-Sen slope and Kendall test
# Run the setup first, then select the calculation or click Source for the whole file.
# Numerical examples describe the workshop dataset and settings.

# Load project helpers and the packaged inputs used below.
# Block 01: Open the shared lesson setup ----
lesson_setup <- "thimphu_WUI/r_studio_run/00_setup.R"
if (!file.exists(lesson_setup)) lesson_setup <- "r_studio_run/00_setup.R"
source(lesson_setup, local = TRUE)

# Block 02: Run the short exercise and read its output ----

an <- read.csv(tw("data/derived/wui_annual_dynamic_world.csv")); full <- an[!an$partial, ]
print(full[, c("year", "built_km2", "wui_km2", "mean_valid_obs")], row.names = FALSE)
ij <- combn(nrow(full), 2); sl <- (full$wui_km2[ij[2, ]] - full$wui_km2[ij[1, ]]) / (full$year[ij[2, ]] - full$year[ij[1, ]])
say("Pairs of years: %d | pairwise slopes from %.1f to %.1f km2/yr", length(sl), min(sl), max(sl))
say("Theil-Sen slope = median of the slopes = %.2f km2/yr", median(sl))
say("Endpoint slope (2025 - 2017) / 8 = %.2f km2/yr", (tail(full$wui_km2, 1) - full$wui_km2[1]) / 8)
kt <- cor.test(full$year, full$wui_km2, method = "kendall", exact = FALSE); say("Kendall tau = %.3f, p = %.4f", kt$estimate, kt$p.value)

