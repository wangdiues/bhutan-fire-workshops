# Fire-management screening | outputs/05-fire-mgmt
# Open the workshop .Rproj and use the actual contents of the participant ZIP.
# Run the setup, then the section blocks with Ctrl+Enter. Source runs the whole file.

# ---- Choose whether to rebuild the result ----
# FALSE reads the packaged reviewed output. Set TRUE in a working copy to rerun
# the existing analysis stages and replace their generated files.
rebuild <- FALSE
if (!file.exists("START_HERE.R")) {
  stop("Open the .Rproj inside the extracted workshop project.", call. = FALSE)
}
source("START_HERE.R", local = TRUE)
if (rebuild) run_project(c("15", "16"))

# ---- Read the cumulative exclusion and eligibility tables ----
# Rows are sequential screening criteria. The cumulative column records what
# remains after applying the current rule and all previous rules.
line <- read.csv("data/derived/fire_mgmt/fire_line_exclusion_funnel.csv")
burn <- read.csv("data/derived/fire_mgmt/rx_eligibility_funnel.csv")
print(line[, c("rule", "cumulative_pieces", "cumulative_km")], row.names = FALSE)
print(burn[, c("rule", "cumulative_cells", "cumulative_ha")], row.names = FALSE)

# ---- Compare the ranking and sensitivity summaries ----
# Screening ranks candidates under the stated inputs and weights. The output is
# for field verification and planning. Do not interpret a score as a probability.
print(read.csv("data/derived/fire_mgmt/sensitivity_fire_lines.csv"))
print(read.csv("data/derived/fire_mgmt/sensitivity_rx_sites.csv"))
# Which constraint removed the most area or length? How stable is the ranking?
