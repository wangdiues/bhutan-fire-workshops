# Lesson 3.1 | Choosing the detection rule (20 candidate rules)
# Run the setup first, then select the calculation or click Source for the whole file.
# Numerical examples describe the workshop dataset and settings.

# Load project helpers and the packaged inputs used below.
source("r_studio_run/00_setup.R", local = TRUE)

cal <- openxlsx::read.xlsx(tp("outputs/01-severity/process_data/fig_03_data.xlsx"))
cal$eligible <- cal$placebo_selection <= SV$max_placebo_rate
cal <- cal[order(-cal$eligible, -cal$detection, cal$min_ha, cal$q), ]
cal[, c("detection", "placebo_selection", "placebo_heldout")] <- round(100 * cal[, c("detection", "placebo_selection", "placebo_heldout")], 1)
print(cal[, c("q", "min_ha", "detection", "placebo_selection", "placebo_heldout", "eligible")], row.names = FALSE)
say("(percentages) Rule chosen: first eligible row = highest detection with <= %.0f%% in the selection zones.", 100 * SV$max_placebo_rate)

