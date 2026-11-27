# Shared helpers for the thimphu_paro_burn_severity package.
# Scripts can be run from the parent project root (Rscript thimphu_paro_burn_severity/scripts/<x>.R) or from inside the
# package folder (Rscript scripts/<x>.R). TP is the package root; everything is read and written below it,
# except that 01_prepare_inputs.R reads the parent project's already-downloaded data once.
suppressPackageStartupMessages({ library(terra); library(sf); library(jsonlite) })
Sys.setenv(TZ = "Asia/Thimphu")   # v1.1: Bhutan time zone (UTC+6), not the machine default (reviewer, editor item 4)

TP <- local({
  # inside the package (any folder name, e.g. after unzipping on a workshop laptop)
  if (file.exists("config/settings.json") && file.exists("R/tp_common.R")) "."
  else if (file.exists("thimphu_paro_burn_severity/config/settings.json")) "thimphu_paro_burn_severity"
  else stop("Run from the parent project root or from inside thimphu_paro_burn_severity/.")
})
tp <- function(...) file.path(TP, ...)
CFG <- read_json(tp("config/settings.json"), simplifyVector = TRUE)
CRS <- CFG$study_area$crs
SCI_OUT_ROOT <- tp("outputs")
dir.create(SCI_OUT_ROOT, showWarnings = FALSE, recursive = TRUE)

study_dzongkhags <- function() st_read(tp("data/inputs/study_area.gpkg"), "dzongkhags", quiet = TRUE)
study_buffer <- function() st_read(tp("data/inputs/study_area.gpkg"), "context_buffer", quiet = TRUE)
study_gewogs <- function() st_read(tp("data/inputs/study_area.gpkg"), "gewogs", quiet = TRUE)

wilson_ci <- function(k, n, z = 1.96) {
  p <- k / n; d <- 1 + z^2 / n
  cbind(low = (p + z^2 / (2 * n) - z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2))) / d,
        high = (p + z^2 / (2 * n) + z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2))) / d)
}

# Severity indices on the NBR x 1000 scale (Miller & Thode 2007; Parks et al. 2014).
# dnbr_c is offset-corrected dNBR (unscaled); pre is pre-fire NBR (unscaled).
idx_rbr <- function(dnbr_c, pre) 1000 * dnbr_c / (pre + 1.001)
idx_rdnbr <- function(dnbr_c, pre) { r <- 1000 * dnbr_c / sqrt(abs(pre)); r[abs(pre) < 1e-3] <- NA; r }

# v1.1: classes are SPECTRAL-CHANGE classes (provisional RBR thresholds), not field-verified ecological severity.
SEV_LEVELS <- c("No detected change", "Low spectral change", "Moderate spectral change", "High spectral change")
SEV_SHORT <- c("None", "Low", "Moderate", "High")   # short tags for tables and file fields
SEV_COLS <- setNames(c("#d9d9d9", "#fee08b", "#f46d43", "#a50026"), SEV_LEVELS)

# Solar elevation and azimuth (degrees; azimuth clockwise from north), NOAA approximation.
# date: Date; hour: local solar-clock hour (Bhutan UTC+6); lon/lat in degrees.
sun_position <- function(date, hour, lon, lat, tz = 6) {
  doy <- as.integer(format(date, "%j")); g <- 2 * pi / 365 * (doy - 1 + (hour - 12) / 24)
  eqt <- 229.18 * (0.000075 + 0.001868 * cos(g) - 0.032077 * sin(g) - 0.014615 * cos(2 * g) - 0.040849 * sin(2 * g))
  decl <- 0.006918 - 0.399912 * cos(g) + 0.070257 * sin(g) - 0.006758 * cos(2 * g) + 0.000907 * sin(2 * g) -
    0.002697 * cos(3 * g) + 0.00148 * sin(3 * g)
  tst <- hour * 60 + eqt + 4 * lon - 60 * tz; ha <- (tst / 4 - 180) * pi / 180; la <- lat * pi / 180
  cz <- sin(la) * sin(decl) + cos(la) * cos(decl) * cos(ha); zen <- acos(pmin(1, pmax(-1, cz)))
  az <- acos(pmin(1, pmax(-1, (sin(la) * cos(zen) - sin(decl)) / (cos(la) * sin(zen))))) * 180 / pi
  az <- ifelse(ha > 0, (az + 180) %% 360, (540 - az) %% 360)
  c(elevation = 90 - zen * 180 / pi, azimuth = az)
}

# Cosine of the local solar incidence angle from slope/aspect rasters in radians.
cos_incidence <- function(slope, aspect, sun) {
  z <- (90 - sun[["elevation"]]) * pi / 180; a <- sun[["azimuth"]] * pi / 180
  cos(z) * cos(slope) + sin(z) * sin(slope) * cos(a - aspect)
}

aspect_class <- function(deg) {
  lab <- c("N", "NE", "E", "SE", "S", "SW", "W", "NW")
  factor(lab[(floor((deg + 22.5) %% 360 / 45)) + 1], levels = lab)
}

write_json_pretty <- function(x, path) writeLines(toJSON(x, auto_unbox = TRUE, pretty = TRUE, digits = NA), path)
