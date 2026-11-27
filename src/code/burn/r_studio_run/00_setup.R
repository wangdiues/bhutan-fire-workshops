# Open the workshop .Rproj before sourcing this setup.
if (!file.exists("config/settings.json")) {
  stop("Open the workshop .Rproj from the extracted participant ZIP.", call. = FALSE)
}
source("R/tp_common.R", local = TRUE)
terraOptions(progress = 0)
options(width = 200)
set.seed(20261124)
SV <- CFG$severity; WIN <- SV$windows; PL <- SV$placebo; TH <- SV$thermal
EV <- tp("data/raw/events"); ES <- tp("data/raw/events_seasonal"); VD <- tp("data/inputs/validation"); DER <- tp("data/derived")
dir.create(tp("logs"), showWarnings = FALSE)
say <- function(...) cat(sprintf(...), "\n", sep = "")
hr  <- function(title) cat("\n==== ", title, " ====\n", sep = "")
png_out <- function(name, w = 1500, h = 900) { f <- tp("logs", paste0("lesson_", name, ".png")); png(f, w, h, res = 150); f }

# ---- the example fire, prepared exactly as in 02_severity_mapping.R (prep) ------------------------------------------
read_window <- function(tag, tmpl) {
  if (tag %in% c("pre90", "p90")) {                                    # v1.0 adjacent windows: one file per window
    f <- file.path(EV, sprintf("%s_%s.tif", KEY, ifelse(tag == "pre90", "pre", "post"))); r <- rast(f); m <- fromJSON(sub("[.]tif$", ".json", f))
    return(list(nbr = r[["nbr_x10000"]] / 1e4, ndvi = r[["ndvi_x10000"]] / 1e4, n = r[["valid_observations"]], start = m$window_start, end = m$window_end_exclusive, n_images = length(m$source_images)))
  }
  f <- file.path(ES, paste0(KEY, ".tif")); m <- fromJSON(sub("[.]tif$", ".json", f)); w <- m$windows[[tag]]   # v1.1 seasonal: one file, 12 bands
  r <- rast(f); r[r == -32768] <- NA
  names(r) <- unlist(lapply(names(m$windows), function(t) paste0(c("nbr_", "ndvi_", "n_"), t)))
  out <- list(nbr = r[[paste0("nbr_", tag)]] / 1e4, ndvi = r[[paste0("ndvi_", tag)]] / 1e4, n = r[[paste0("n_", tag)]], start = w$start, end = w$end_exclusive, n_images = w$n_images)
  for (b in c("nbr", "ndvi", "n")) if (!compareGeom(out[[b]], tmpl, stopOnError = FALSE)) out[[b]] <- resample(extend(crop(out[[b]], tmpl), tmpl), tmpl, "near")
  out
}
example <- function() {
  inc <- read.csv(tp("data/inputs/dofps_incidents_paro_thimphu.csv"), stringsAsFactors = FALSE)
  ev <- inc[inc$event_id == EXAMPLE, ]
  tmpl <- rast(file.path(EV, paste0(KEY, "_pre.tif")))[[1]]
  pre <- read_window("preM", tmpl); post <- read_window("p90", tmpl)
  pt <- vect(st_transform(st_as_sf(ev, coords = c("longitude", "latitude"), crs = 4326), CRS))
  g <- pre$nbr; dist <- distance(g, pt)
  dm <- resample(crop(rast(tp("data/inputs/dem_30m.tif")), ext(g) + 200), g, "bilinear")
  slope <- terrain(dm, "slope", unit = "radians"); aspect <- terrain(dm, "aspect", unit = "radians")
  w <- as.Date(c(post$start, post$end)); mid <- w[1] + as.integer(diff(w) / 2)
  sun <- sun_position(mid, SV$overpass_local_time_h, ev$longitude, ev$latitude)
  cosi <- cos_incidence(slope, aspect, sun)
  V <- data.frame(dnbr = values(g - post$nbr, mat = FALSE), pre = values(g, mat = FALSE), post = values(post$nbr, mat = FALSE),
                  ndvi = values(pre$ndvi, mat = FALSE), cosi = values(cosi, mat = FALSE), dist = values(dist, mat = FALSE))
  V$veg <- V$ndvi >= SV$min_pre_ndvi_vegetated; V$lit <- V$cosi >= SV$min_cos_illumination
  usable <- is.finite(V$dnbr) & is.finite(V$pre) & V$veg %in% TRUE & V$lit %in% TRUE
  ring <- usable & V$dist >= SV$reference_ring_m[1] & V$dist <= SV$reference_ring_m[2]
  off <- median(V$dnbr[ring]); V$dnbr_c <- V$dnbr - off; V$rbr <- idx_rbr(V$dnbr_c, V$pre); V$rdnbr <- idx_rdnbr(V$dnbr_c, V$pre)
  list(ev = ev, pre = pre, post = post, g = g, pt = pt, V = V, usable = usable, ring = ring, off = off, sun = sun, cosi = cosi, px_ha = prod(res(g)) / 1e4)
}
patches_of <- function(P, thr) {    # candidate pixels -> numbered 8-connected patches (as lab_patches in script 02)
  cand <- P$usable & P$V$dnbr_c >= SV$unburned_low_dnbr_x1000 / 1000 & P$V$rbr >= thr
  values(patches(setValues(P$g, ifelse(cand, 1, NA)), directions = 8), mat = FALSE)
}
detect <- function(P, q, min_ha, grow = TRUE, radius = SV$search_radius_m) {   # as candidates() + apply_rule() in script 02
  thr <- unname(quantile(P$V$rbr[P$ring], q)); pv <- patches_of(P, thr)
  big <- as.integer(names(which(table(pv) >= max(2, ceiling(min_ha / P$px_ha)))))
  keep <- intersect(unique(pv[P$V$dist <= radius & !is.na(pv)]), big); seed <- pv %in% keep
  if (grow && length(keep)) { gl <- patches_of(P, min(thr, unname(quantile(P$V$rbr[P$ring], SV$grow_quantile)))); keep <- unique(gl[seed & !is.na(gl)]); pv <- gl }
  list(thr = thr, pv = pv, big = big, keep = keep, inpatch = pv %in% keep)
}
RES <- function() fromJSON(tp("data/derived/results_severity.json"), simplifyVector = TRUE)


# Example identifiers are supplied in the participant package.
training_example <- function(name) {
  file <- tp("config/training_examples.json")
  if (!file.exists(file)) stop("Extract the participant ZIP. Missing: ", file, call. = FALSE)
  value <- jsonlite::read_json(file)[[name]]
  if (!is.character(value) || length(value) != 1L || !nzchar(value))
    stop("Missing training example setting: ", name, call. = FALSE)
  value
}
