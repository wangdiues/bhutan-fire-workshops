# Open the workshop .Rproj before sourcing this setup.
if (!file.exists("config/settings.json")) {
  stop("Open the workshop .Rproj from the extracted participant ZIP.", call. = FALSE)
}
source("R/tw_common.R", local = TRUE)
terraOptions(progress = 0)
options(width = 200)
set.seed(20261124)
km2 <- (RES / 1000)^2                                    # one 50 m cell = 0.0025 km2
LAY <- tw("data/derived/layers")
dir.create(tw("logs"), showWarnings = FALSE)
say <- function(...) cat(sprintf(...), "\n", sep = "")
hr  <- function(title) cat("\n==== ", title, " ====\n", sep = "")
png_out <- function(name) { f <- tw("logs", paste0("lesson_", name, ".png")); png(f, 1400, 1000, res = 150); f }

# A 10 km x 10 km teaching window centred on the densest settlement (Thimphu city), so lessons run in seconds.
window <- function() {
  ob <- st_read(tw("data/inputs/buildings.gpkg"), "open_buildings_v3", quiet = TRUE)
  xy <- st_coordinates(ob[ob$confidence >= CFG$buildings$confidence_min, ])
  cx <- median(xy[, 1]); cy <- median(xy[, 2])
  ext(cx - 5000, cx + 5000, cy - 5000, cy + 5000)
}

B03 <- function() {   # buildings inside Thimphu and their distance to fire evidence (used by lessons 3.x)
  g <- grid50(); zone <- values(g, mat = FALSE); inside <- which(zone %in% 2)
  ob <- st_read(tw("data/inputs/buildings.gpkg"), "open_buildings_v3", quiet = TRUE); ob <- ob[ob$confidence >= CFG$buildings$confidence_min, ]
  bcell <- cellFromXY(g, st_coordinates(ob)); keep <- !is.na(bcell) & zone[bcell] %in% 2
  fe <- tw("data/inputs/fire_evidence.gpkg")
  ev <- cover(cover(rasterize(vect(st_read(fe, "dofps_points", quiet = TRUE)), g, field = 1),
                    rasterize(vect(st_read(fe, "burned_patches", quiet = TRUE)), g, field = 1, touches = TRUE)),
              rasterize(vect(st_read(fe, "firms_points", quiet = TRUE)), g, field = 1))
  dist <- values(distance(ev), mat = FALSE)[bcell[keep]]
  gid <- rast(tw("data/inputs/gewog_50m.tif")); glev <- levels(gid)[[1]]
  unit <- glev[[2]][match(values(gid, mat = FALSE), glev[[1]])][bcell[keep]]; unit[is.na(unit)] <- CFG$study_area$unassigned_unit
  list(g = g, inside = inside, bidx = match(bcell[keep], inside), dist = dist, unit = unit, fire = dist <= CFG$fire_evidence$exposure_distance_m)
}
rule_wui <- function(B, x) {   # WUI yes/no for every building under rule x
  v <- function(f, lyr) values(rast(file.path(LAY, f))[[lyr]], mat = FALSE)[B$inside]
  d <- v("density_ob.tif", paste0("r", x$R)); vp <- v(sprintf("vegpct_%s.tif", x$veg), paste0("r", x$R)); p <- v(sprintf("patchdist_%s.tif", x$veg), paste0("a", x$A))
  (classify_wui(d, vp, ifelse(is.na(p), Inf, p), x$D, x$V, x$P) %in% 1:2)[B$bidx]
}
cm <- function(w, e) { tp <- sum(w & e); fn <- sum(!w & e); fp <- sum(w & !e); tn <- sum(!w & !e)
  c(TP = tp, FN = fn, FP = fp, TN = tn, sens = tp / (tp + fn), spec = tn / (tn + fp), J = tp / (tp + fn) + tn / (tn + fp) - 1) }
SELR <- list(D = 20, V = 50, P = 100, R = 1000, A = 5, veg = "wc_woody_grass")
