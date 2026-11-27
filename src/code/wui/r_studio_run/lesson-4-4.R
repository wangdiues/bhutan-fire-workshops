# Lesson 4.4 | Majority of three years (stable / new / lost)
# Run the setup first, then select the calculation or click Source for the whole file.
# Numerical examples describe the workshop dataset and settings.

# Load project helpers and the packaged inputs used below.
# Block 01: Open the shared lesson setup ----
lesson_setup <- "thimphu_WUI/r_studio_run/00_setup.R"
if (!file.exists(lesson_setup)) lesson_setup <- "r_studio_run/00_setup.R"
source(lesson_setup, local = TRUE)

# Block 02: Run the short exercise and read its output ----

ex <- data.frame(cell = c("a", "b", "c", "d", "e"), y2017 = c(1, 0, 1, 0, 1), y2018 = c(1, 0, 1, 1, 0), y2019 = c(1, 0, 0, 0, 0),
                 y2023 = c(1, 1, 0, 1, 1), y2024 = c(1, 1, 0, 1, 0), y2025 = c(0, 1, 0, 1, 0))
ex$early <- rowSums(ex[, 2:4]) >= 2; ex$late <- rowSums(ex[, 5:7]) >= 2
ex$change <- ifelse(ex$early & ex$late, "stable WUI", ifelse(!ex$early & ex$late, "new WUI", ifelse(ex$early & !ex$late, "lost WUI", "never WUI")))
print(ex, row.names = FALSE)
r <- rast(tw("data/derived/wui_change_2017_19_to_2023_25_50m.tif")); print(freq(r)); say("(count x 0.0025 = km2)")

