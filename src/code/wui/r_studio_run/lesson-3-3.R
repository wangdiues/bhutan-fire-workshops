# Lesson 3.3 | Change one parameter (P) and watch J
# Run the setup first, then select the calculation or click Source for the whole file.
# Numerical examples describe the workshop dataset and settings.

# Load project helpers and the packaged inputs used below.
# Block 01: Open the shared lesson setup ----
lesson_setup <- "thimphu_WUI/r_studio_run/00_setup.R"
if (!file.exists(lesson_setup)) lesson_setup <- "r_studio_run/00_setup.R"
source(lesson_setup, local = TRUE)

# Block 02: Run the short exercise and read its output ----

B <- B03()
out <- do.call(rbind, lapply(CFG$sensitivity_grid$P, function(p) { x <- SELR; x$P <- p; w <- rule_wui(B, x); r <- cm(w, B$fire)
  data.frame(P_m = p, buildings_in_WUI_pct = round(100 * mean(w), 1), sensitivity = round(r[["sens"]], 3), specificity = round(r[["spec"]], 3), J = round(r[["J"]], 3)) }))
print(out, row.names = FALSE)
hr("Top 10 of all 2,160 rules (from step 03: data/derived/calibration_all_rules.csv)")
sc <- read.csv(tw("data/derived/calibration_all_rules.csv"), check.names = FALSE)
print(head(sc[order(sc$rank), c("rank", "D", "V", "P", "R", "A", "veg", "wui_km2", "building_share", "J_all@1000")], 10), row.names = FALSE)

