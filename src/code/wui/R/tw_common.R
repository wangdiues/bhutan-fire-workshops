# Shared helpers for the thimphu_WUI package (wildland-urban interface of Thimphu dzongkhag).
# Run scripts from the parent project root (Rscript thimphu_WUI/scripts/<x>.R) or from inside the package folder.
# TW is the package root. Core replay (02-05 and 08) uses packaged inputs.
# Optional preparation (01), parent-data audit (10) and acquisition (11) also read parent-project resources.
suppressPackageStartupMessages({ library(terra); library(sf); library(jsonlite) })

TW <- local({
  if (file.exists("config/settings.json")) "."
  else if (file.exists("thimphu_WUI/config/settings.json")) "thimphu_WUI"
  else stop("Run from the parent project root or from inside thimphu_WUI/.")
})
tw <- function(...) file.path(TW, ...)
CFG <- read_json(tw("config/settings.json"), simplifyVector = TRUE)
CRS <- CFG$study_area$crs
RES <- CFG$grid$resolution_m
SCI_OUT_ROOT <- tw("outputs")
dir.create(SCI_OUT_ROOT, showWarnings = FALSE, recursive = TRUE)
sf_use_s2(FALSE)

CLASSES <- c("intermix", "interface", "non-WUI vegetated", "non-WUI developed", "non-WUI other")
WUI_COLS <- c(intermix = "#D55E00", interface = "#E69F00", `non-WUI vegetated` = "#009E73",
              `non-WUI developed` = "#555555", `non-WUI other` = "#dddddd")
VEG_LABEL <- c(ftm = "Forest-type map (forest + scrub)", wc_woody = "WorldCover tree + shrub", wc_woody_grass = "WorldCover tree + shrub + grass")

study_dz <- function() st_read(tw("data/inputs/study_area.gpkg"), "dzongkhag", quiet = TRUE)
study_buffer <- function() st_read(tw("data/inputs/study_area.gpkg"), "context_buffer", quiet = TRUE)
study_gewogs <- function() st_read(tw("data/inputs/study_area.gpkg"), "gewogs", quiet = TRUE)
grid50 <- function() rast(tw("data/inputs/grid_50m.tif"))

# Radeloff-type classification of cell vectors: d = building density (/km2), v = vegetation (%), p = distance (m)
# to a large vegetated patch. 1 intermix, 2 interface, 3 non-WUI vegetated, 4 non-WUI developed, 5 non-WUI other.
classify_wui <- function(d, v, p, D, V, P) {
  out <- ifelse(d > D, ifelse(v >= V, 1L, ifelse(p <= P, 2L, 4L)), ifelse(v >= V, 3L, 5L))
  out[is.na(d) | is.na(v)] <- NA_integer_
  out
}
circle_w <- function(g, r) { w <- focalMat(g, r, "circle"); w[w > 0] <- 1; w }

wilson_ci <- function(k, n, z = 1.96) {
  p <- k / n; d <- 1 + z^2 / n
  cbind(low = (p + z^2 / (2 * n) - z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2))) / d,
        high = (p + z^2 / (2 * n) + z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2))) / d)
}
write_json_pretty <- function(x, path) writeLines(toJSON(x, auto_unbox = TRUE, pretty = TRUE, digits = NA), path)
md_kappa <- function(a, b, levels) {
  cm <- table(factor(a, levels), factor(b, levels)); po <- sum(diag(cm)) / sum(cm); pe <- sum(rowSums(cm) * colSums(cm)) / sum(cm)^2
  c(agreement = po, kappa = (po - pe) / (1 - pe))
}
