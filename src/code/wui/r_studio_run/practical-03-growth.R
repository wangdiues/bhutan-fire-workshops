# Dynamic World settlement-proxy change | outputs/03-growth
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
if (rebuild) run_project(c("04"))

# ---- Read annual coverage and distinguish complete and partial years ----
annual <- read.csv("data/derived/wui_annual_dynamic_world.csv")
print(annual[, c("year", "partial", "wui_km2", "mean_valid_obs")])
complete <- subset(annual, !partial)
stopifnot(nrow(complete) > 1)

# ---- Calculate a simple robust slope from the complete years ----
pair <- utils::combn(seq_len(nrow(complete)), 2)
slope <- diff(matrix(complete$wui_km2[pair], nrow = 2)) /
  diff(matrix(complete$year[pair], nrow = 2))
cat("Median pairwise slope, km2/year:", median(slope), "\n")
plot(complete$year, complete$wui_km2, type = "b", xlab = "Year",
  ylab = "WUI settlement proxy (km2)")
# The series measures land-cover proxies. Compare coverage before reading trends.
