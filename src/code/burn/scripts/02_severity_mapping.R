# 02  Satellite detection and provisional spectral-change mapping of DoFPS fire incidents, Paro and Thimphu (v1.1)
# v1.1 responds to the peer review of v1.0 (docs/RESPONSE_TO_REVIEWERS.md). Method:
#  1. Composites: season-matched pre-fire window (same 90 days one year before the fire, "preM") and the 90-day
#     post-fire window ("p90"); incidents without a usable preM composite fall back to the v1.0 adjacent 90-day pre
#     window ("pre90"). All windows, acquisition dates and valid-observation counts are reported per incident.
#  2. dNBR = NBR_pre - NBR_post; offset = median dNBR of usable pixels in a 2-5 km ring; dNBR_c = dNBR - offset;
#     RBR = 1000 dNBR_c / (NBR_pre + 1.001) (Parks et al. 2014); RdNBR = 1000 dNBR_c / sqrt(|NBR_pre|).
#  3. Masks: pre-fire NDVI < 0.2, terrain shadow (cos i < 0.15 for the sun at the post-window mid-date, 10:30 overpass),
#     missing data.
#  4. Detection: candidates dNBR_c >= 0.100 and RBR > ring quantile q; 8-connected patches >= min area touching the
#     500 m search zone. (q, min area) chosen on SELECTION placebo zones only; HELD-OUT placebo zones (three distance
#     bands) and independent thermal evidence (FIRMS, MODIS MCD64A1) evaluate it. Placebo zones are not verified
#     fire-free: their rate is a background-detection rate, not a false-positive rate.
#  5. Delineation by hysteresis growth (ring 95th percentile). Classes: provisional SPECTRAL-CHANGE classes from RBR
#     (116 / 283, Parks et al. 2018), not field-verified ecological severity.
#  6. Sensitivity: window configurations, search radius (100-1,000 m), sensors analysed separately, eligible rules.
#  7. Atlas: event maps, unique burned area, repeat burns, first / latest fire year, highest spectral class.
# Run: Rscript thimphu_paro_burn_severity/scripts/02_severity_mapping.R
source(if (file.exists("thimphu_paro_burn_severity/R/tp_common.R")) "thimphu_paro_burn_severity/R/tp_common.R" else "R/tp_common.R")
source(tp("R/sci_figure.R"))
suppressPackageStartupMessages({ library(patchwork); library(lme4); library(spdep) })
# v1.1: terra temp files go to drive D (drive C has ~11 GB free and filled up); cleared per incident and at the end.
TMPD <- normalizePath(tp("_tmp_terra"), mustWork = FALSE); dir.create(TMPD, showWarnings = FALSE)
terraOptions(memfrac = 0.4, tempdir = TMPD, progress = 0)
on.exit(unlink(TMPD, recursive = TRUE), add = TRUE)
set.seed(20261124)
# ============================================================
# CONFIGURATION
# ============================================================
SV <- CFG$severity; WIN <- SV$windows; PL <- SV$placebo; TH <- SV$thermal
band_rng <- function(b) as.numeric(if (is.matrix(PL$bands_m)) PL$bands_m[b, ] else PL$bands_m[[b]])   # JSON may load as matrix
n_bands <- if (is.matrix(PL$bands_m)) nrow(PL$bands_m) else length(PL$bands_m)
SLUG <- "01-severity"
EV <- tp("data/raw/events"); ES <- tp("data/raw/events_seasonal"); VD <- tp("data/inputs/validation"); DER <- tp("data/derived")
DWNAME <- c(`0` = "Water", `1` = "Trees", `2` = "Grass", `3` = "Flooded vegetation", `4` = "Crops", `5` = "Shrub and scrub", `6` = "Built", `7` = "Bare", `8` = "Snow and ice")
WCNAME <- c(`10` = "Tree cover", `20` = "Shrubland", `30` = "Grassland", `40` = "Cropland", `50` = "Built-up", `60` = "Bare / sparse", `70` = "Snow and ice", `80` = "Water", `90` = "Wetland", `95` = "Mangroves", `100` = "Moss and lichen")
# ============================================================
inc <- read.csv(tp("data/inputs/dofps_incidents_paro_thimphu.csv"), stringsAsFactors = FALSE); inc <- inc[inc$in_study_area, ]
inv <- read.csv(tp("data/inputs/event_imagery_inventory.csv"))
pairs <- unique(inv[inv$status == "downloaded", c("event_id", "sensor")])
pairs <- pairs[mapply(function(e, s) all(file.exists(file.path(EV, sprintf("%s_%s_%s.tif", e, s, c("pre", "post"))))), pairs$event_id, pairs$sensor), ]
# Workshop quick mode: TP_MAX_PAIRS=N analyses only the first N incident-sensor pairs (demonstration only; results are partial).
MAXP <- suppressWarnings(as.integer(Sys.getenv("TP_MAX_PAIRS", "0"))); if (!is.na(MAXP) && MAXP > 0) { pairs <- head(pairs, MAXP); message("QUICK MODE: first ", MAXP, " pairs only - results are a demonstration, not the full analysis") }
yrs <- range(as.integer(substr(inc$start_date_local[inc$event_id %in% pairs$event_id], 1, 4)))
TITLE <- sprintf("Satellite detection and provisional spectral-change mapping of DoFPS fire incidents, Paro and Thimphu, %d-%d", yrs[1], yrs[2])
unlink(file.path(SCI_OUT_ROOT, SLUG), recursive = TRUE); unlink(file.path(DER, "severity_rasters"), recursive = TRUE)
run <- sci_run(SLUG, TITLE, inputs = c(file.path(EV, "x"), file.path(ES, "x"), tp("data/inputs/x")))
for (d in c("severity_rasters", "RESTRICTED")) dir.create(file.path(DER, d), recursive = TRUE, showWarnings = FALSE)
dem <- rast(tp("data/inputs/dem_30m.tif")); ftype <- rast(tp("data/inputs/forest_type_50m.tif")); ft_lev <- levels(ftype)[[1]]
pts <- st_transform(st_as_sf(inc, coords = c("longitude", "latitude"), crs = 4326, remove = FALSE), CRS)
firms <- read.csv(file.path(VD, "firms_points.csv")); firms$date <- as.Date(firms$date)
mcd <- read.csv(file.path(VD, "mcd64a1_burned_pixels.csv")); mcd$date <- as.Date(mcd$date)
therm <- rbind(data.frame(src = "FIRMS", x = firms$x, y = firms$y, date = firms$date), data.frame(src = "MCD64A1", x = mcd$x, y = mcd$y, date = mcd$date))

# ---- layer readers: v1.0 adjacent windows (pre90, p90) and v1.1 seasonal windows (preM, p30, p60, ext) -------------------
img_dates <- function(ids) sort(unique(vapply(ids, function(i) { b <- sub(".*/", "", i); regmatches(b, regexpr("\\d{8}", b)) }, "")))
layer <- function(key, tag, tmpl) {
  if (tag %in% c("pre90", "p90")) {
    f <- file.path(EV, sprintf("%s_%s.tif", key, ifelse(tag == "pre90", "pre", "post"))); r <- rast(f); m <- fromJSON(sub("[.]tif$", ".json", f))
    out <- list(nbr = r[["nbr_x10000"]] / 1e4, ndvi = r[["ndvi_x10000"]] / 1e4, n = r[["valid_observations"]],
                start = m$window_start, end = m$window_end_exclusive, n_images = length(m$source_images), dates = img_dates(m$source_images))
  } else {
    f <- file.path(ES, paste0(key, ".tif")); if (!file.exists(f) || !file.exists(sub("[.]tif$", ".json", f))) return(NULL)
    m <- fromJSON(sub("[.]tif$", ".json", f)); w <- m$windows[[tag]]; if (is.null(w) || w$n_images < WIN$min_valid_obs) return(NULL)
    r <- rast(f); r[r == -32768] <- NA
    names(r) <- unlist(lapply(names(m$windows), function(t) paste0(c("nbr_", "ndvi_", "n_"), t)))   # GeoTIFF band order set by 00_acquire
    out <- list(nbr = r[[paste0("nbr_", tag)]] / 1e4, ndvi = r[[paste0("ndvi_", tag)]] / 1e4, n = r[[paste0("n_", tag)]],
                start = w$start, end = w$end_exclusive, n_images = w$n_images, dates = gsub("-", "", w$image_dates))
  }
  if (!is.null(tmpl)) for (b in c("nbr", "ndvi", "n")) if (!compareGeom(out[[b]], tmpl, stopOnError = FALSE)) out[[b]] <- resample(extend(crop(out[[b]], tmpl), tmpl), tmpl, "near")
  if (all(is.na(values(out$nbr)))) return(NULL)
  out
}
fmt_dates <- function(d) if (!length(d)) "" else sprintf("%s to %s (%d dates)", format(as.Date(min(d), "%Y%m%d")), format(as.Date(max(d), "%Y%m%d")), length(d))

# ---- one incident x sensor x window configuration --------------------------------------------------------------------
prep <- function(k, cfg) {
  e <- pairs$event_id[k]; s <- pairs$sensor[k]; key <- paste(e, s, sep = "_")
  tmpl <- rast(file.path(EV, paste0(key, "_pre.tif")))[[1]]   # v1.0 grid is the master grid for every configuration
  pre <- layer(key, cfg[1], tmpl); post <- layer(key, cfg[2], tmpl)
  if (is.null(pre) || is.null(post)) return(NULL)
  g <- pre$nbr; pt <- vect(pts[pts$event_id == e, ]); dist <- distance(g, pt)
  dm <- resample(crop(dem, ext(g) + 200), g, "bilinear")
  slope <- terrain(dm, "slope", unit = "radians"); aspect <- terrain(dm, "aspect", unit = "radians")
  w <- as.Date(c(post$start, post$end)); mid <- w[1] + as.integer(diff(w) / 2)
  sun <- sun_position(mid, SV$overpass_local_time_h, inc$longitude[inc$event_id == e], inc$latitude[inc$event_id == e])
  cosi <- cos_incidence(slope, aspect, sun)
  veg <- pre$ndvi >= SV$min_pre_ndvi_vegetated; lit <- cosi >= SV$min_cos_illumination
  V <- data.frame(dnbr = values(g - post$nbr, mat = FALSE), pre = values(g, mat = FALSE), veg = values(veg, mat = FALSE) == 1,
                  lit = values(lit, mat = FALSE) == 1, dist = values(dist, mat = FALSE))
  usable <- is.finite(V$dnbr) & is.finite(V$pre) & V$veg %in% TRUE & V$lit %in% TRUE
  ring <- usable & V$dist >= SV$reference_ring_m[1] & V$dist <= SV$reference_ring_m[2]
  ok <- sum(ring) >= 50 && sum(V$dist <= SV$search_radius_m & is.finite(V$dnbr)) >= 5
  off <- if (ok) median(V$dnbr[ring]) else NA
  V$dnbr_c <- V$dnbr - off; V$rbr <- idx_rbr(V$dnbr_c, V$pre); V$rdnbr <- idx_rdnbr(V$dnbr_c, V$pre)
  # placebo zones: fixed per pair (same seed for every configuration), 3 distance bands x 8 zones
  set.seed(1000 + k); ctr <- crds(pt); xy_all <- xyFromCell(g, seq_len(ncell(g)))
  zones <- do.call(rbind, lapply(seq_len(n_bands), function(b) do.call(rbind, lapply(seq_len(PL$zones_per_band), function(j) {
    a <- runif(1, 0, 2 * pi); r0 <- runif(1, band_rng(b)[1], band_rng(b)[2])
    data.frame(band = b, zone = j, cx = ctr[1] + r0 * cos(a), cy = ctr[2] + r0 * sin(a)) }))))
  zones$selection <- zones$band == PL$selection_band & zones$zone %in% PL$selection_zones
  plz <- lapply(seq_len(nrow(zones)), function(i) which(sqrt((xy_all[, 1] - zones$cx[i])^2 + (xy_all[, 2] - zones$cy[i])^2) <= SV$search_radius_m))
  list(e = e, s = s, key = key, pre = pre, post = post, g = g, pt = pt, ctr = ctr, dm = dm, slope = slope, aspect = aspect, cosi = cosi, sun = sun,
       V = V, usable = usable, ring = ring, ok = ok, off = off, zones = zones, plz = plz, px_ha = prod(res(g)) / 1e4, cfg = cfg)
}
lab_patches <- function(P, thr) {
  cand <- P$usable & P$V$dnbr_c >= SV$unburned_low_dnbr_x1000 / 1000 & P$V$rbr >= thr
  values(patches(setValues(P$g, ifelse(cand, 1, NA)), directions = 8), mat = FALSE)
}
candidates <- function(P, q) { thr <- unname(quantile(P$V$rbr[P$ring], q)); list(thr = thr, pv = lab_patches(P, thr)) }
apply_rule <- function(P, C, min_ha, grow = FALSE, radius = SV$search_radius_m) {
  min_px <- max(2, ceiling(min_ha / P$px_ha)); pv <- C$pv
  big <- as.integer(names(which(table(pv) >= min_px)))
  keep_id <- intersect(unique(pv[P$V$dist <= radius & !is.na(pv)]), big); seed <- pv %in% keep_id
  if (grow && length(keep_id)) {
    gl <- lab_patches(P, min(C$thr, unname(quantile(P$V$rbr[P$ring], SV$grow_quantile))))
    keep_id <- unique(gl[seed & !is.na(gl)]); pv <- gl
  }
  inpatch <- pv %in% keep_id
  plc <- vapply(P$plz, function(z) { if (length(z) < 10 || any(inpatch[z]) || mean(P$usable[z]) < 0.5) return(NA)   # zones off the image are unusable
    any(unique(C$pv[z][!is.na(C$pv[z])]) %in% big) }, NA)
  list(keep_id = keep_id, inpatch = inpatch, plc = plc, pv = pv)
}
thermal_near <- function(cx, cy, fd, r = TH$radius_m) {
  s <- therm$date >= fd - TH$days_before & therm$date <= fd + TH$days_after & sqrt((therm$x - cx)^2 + (therm$y - cy)^2) <= r
  c(firms = sum(s & therm$src == "FIRMS"), mcd = sum(s & therm$src == "MCD64A1"))
}
main_cfg <- function(k) { P <- prep(k, WIN$main); if (!is.null(P) && P$ok) return(P); P <- prep(k, WIN$fallback); if (!is.null(P)) P$fallback <- TRUE; P }

# ---- 1. calibration on SELECTION placebo zones (main configuration) --------------------------------------------------------
GRID <- expand.grid(q = SV$noise_quantile_grid, min_ha = SV$min_patch_ha_grid)
cal <- list(); PCACHE <- list()
for (k in seq_len(nrow(pairs))) {
  P <- main_cfg(k); if (is.null(P) || !P$ok) next
  for (q in unique(GRID$q)) { C <- candidates(P, q)
    for (mh in GRID$min_ha[GRID$q == q]) { R <- apply_rule(P, C, mh); s <- P$zones$selection; h <- !s
      cal[[length(cal) + 1]] <- data.frame(key = P$key, q = q, min_ha = mh, detected = length(R$keep_id) > 0,
        sel_zones = sum(!is.na(R$plc[s])), sel_hits = sum(R$plc[s], na.rm = TRUE), held_zones = sum(!is.na(R$plc[h])), held_hits = sum(R$plc[h], na.rm = TRUE)) } }
}
cal <- do.call(rbind, cal)
CAL <- do.call(rbind, lapply(split(cal, list(cal$q, cal$min_ha)), function(d) data.frame(q = d$q[1], min_ha = d$min_ha[1], detection = mean(d$detected),
  placebo_selection = sum(d$sel_hits) / sum(d$sel_zones), placebo_heldout = sum(d$held_hits) / sum(d$held_zones), zones_selection = sum(d$sel_zones), zones_heldout = sum(d$held_zones))))
CAL$eligible <- CAL$placebo_selection <= SV$max_placebo_rate
best <- if (any(CAL$eligible)) CAL[CAL$eligible, ][order(-CAL$detection[CAL$eligible], CAL$min_ha[CAL$eligible], CAL$q[CAL$eligible]), ][1, ] else CAL[which.min(CAL$placebo_selection), ]
Q_SEL <- best$q; MINHA_SEL <- best$min_ha
message(sprintf("Rule (selection zones): q %.3f, min %.2f ha -> detection %.0f%%, selection-zone rate %.1f%%, held-out rate %.1f%%",
                Q_SEL, MINHA_SEL, 100 * best$detection, 100 * best$placebo_selection, 100 * best$placebo_heldout))

# ---- 2. main mapping, held-out placebo, thermal evidence, radius sensitivity ------------------------------------------------
metrics <- list(); patch_rows <- list(); pix_rows <- list(); polys <- list(); cls_files <- character(); zone_rows <- list(); radius_rows <- list(); vec_main <- list()
for (k in seq_len(nrow(pairs))) {
  P <- main_cfg(k); e <- pairs$event_id[k]; s <- pairs$sensor[k]; key <- paste(e, s, sep = "_")
  if (is.null(P) || !P$ok) { metrics[[key]] <- data.frame(event_id = e, sensor = s, status = "insufficient_valid_pixels"); next }
  g <- P$g; V <- P$V; ev <- inc[inc$event_id == e, ]; fd <- as.Date(ev$start_date_local)
  C <- candidates(P, Q_SEL); R <- apply_rule(P, C, MINHA_SEL, grow = TRUE)
  inpatch <- R$inpatch; pv <- R$pv; keep_id <- R$keep_id
  sev <- rep(NA_integer_, nrow(V)); sev[P$usable] <- 0L
  sev[inpatch] <- as.integer(cut(V$rbr[inpatch], c(-Inf, SV$rbr_low_moderate, SV$rbr_moderate_high, Inf), right = FALSE))
  vec_main[[key]] <- sev
  px_ha <- P$px_ha; ft <- values(resample(ftype, g, "near"), mat = FALSE)
  tn <- thermal_near(P$ctr[1], P$ctr[2], fd)
  # thermal evidence inside or within 500 m of mapped patches
  in_patch_thermal <- if (any(inpatch)) { pxy <- xyFromCell(g, which(inpatch)); tw <- therm[therm$date >= fd - TH$days_before & therm$date <= fd + TH$days_after, ]
    tw <- tw[tw$x > min(pxy[, 1]) - 600 & tw$x < max(pxy[, 1]) + 600 & tw$y > min(pxy[, 2]) - 600 & tw$y < max(pxy[, 2]) + 600, ]
    if (nrow(tw)) any(vapply(seq_len(nrow(tw)), function(i) min((pxy[, 1] - tw$x[i])^2 + (pxy[, 2] - tw$y[i])^2) <= 500^2, TRUE)) else FALSE } else NA
  # later incidents within 5.5 km whose start falls inside this incident's post window (possible contamination)
  others <- inc[inc$event_id != e & as.Date(inc$start_date_local) > fd & as.Date(inc$start_date_local) < as.Date(P$post$end), ]
  later <- if (nrow(others)) sum(sqrt((st_coordinates(pts[match(others$event_id, pts$event_id), ])[, 1] - P$ctr[1])^2 +
                                       (st_coordinates(pts[match(others$event_id, pts$event_id), ])[, 2] - P$ctr[2])^2) <= SV$reference_ring_m[2] + 500) else 0L
  m <- data.frame(event_id = e, sensor = s, status = "analysed", window_config = ifelse(isTRUE(P$fallback), "fallback: adjacent 90 d", "season-matched"),
                  resolution_m = res(g)[1], fire_date = fd, pre_window = paste(P$pre$start, "to", P$pre$end), post_window = paste(P$post$start, "to", P$post$end),
                  pre_images = P$pre$n_images, post_images = P$post$n_images, pre_dates = fmt_dates(P$pre$dates), post_dates = fmt_dates(P$post$dates),
                  later_incidents_in_post_window = later, sun_elevation_deg = P$sun[["elevation"]], ring_offset_dnbr = P$off, ring_iqr_dnbr = IQR(V$dnbr[P$ring]),
                  ring_noise_threshold_rbr = C$thr, inner_usable_share = mean(P$usable[V$dist <= SV$search_radius_m]),
                  inner_shadow_share = mean(!(V$lit[V$dist <= SV$search_radius_m] %in% TRUE)), inner_nonveg_share = mean(!(V$veg[V$dist <= SV$search_radius_m] %in% TRUE)),
                  thermal_firms = tn[["firms"]], thermal_mcd = tn[["mcd"]], thermal_evidence = sum(tn) > 0, thermal_in_patch = in_patch_thermal,
                  n_patches = length(keep_id), detected = length(keep_id) > 0, mapped_area_ha = sum(inpatch) * px_ha,
                  low_ha = sum(sev == 1, na.rm = TRUE) * px_ha, moderate_ha = sum(sev == 2, na.rm = TRUE) * px_ha, high_ha = sum(sev == 3, na.rm = TRUE) * px_ha,
                  mean_rbr = if (any(inpatch)) mean(V$rbr[inpatch]) else NA, reported_area_ha = ev$reported_area_ha, dzongkhag = ev$dzongkhag, report_year = ev$report_year)
  metrics[[key]] <- m
  z <- P$zones; z$key <- key; z$sensor <- s; z$detected <- R$plc
  z$thermal <- vapply(seq_len(nrow(z)), function(i) sum(thermal_near(z$cx[i], z$cy[i], fd)) > 0, TRUE); zone_rows[[key]] <- z
  radius_rows[[key]] <- do.call(rbind, lapply(SV$search_radius_test_m, function(r) { Rr <- apply_rule(P, C, MINHA_SEL, grow = TRUE, radius = r)
    data.frame(key = key, event_id = e, sensor = s, radius_m = r, detected = length(Rr$keep_id) > 0, area_ha = sum(Rr$inpatch) * px_ha) }))
  if (length(keep_id)) {
    xy <- xyFromCell(g, which(inpatch))
    pix <- data.frame(event_id = e, sensor = s, fire_year = as.integer(format(fd, "%Y")), patch = pv[inpatch], x = xy[, 1], y = xy[, 2], pre_nbr = V$pre[inpatch],
                      dnbr_c = V$dnbr_c[inpatch], rbr = V$rbr[inpatch], rdnbr = V$rdnbr[inpatch], class_code = sev[inpatch],
                      elevation_m = values(P$dm, mat = FALSE)[inpatch], slope_deg = values(P$slope, mat = FALSE)[inpatch] * 180 / pi,
                      aspect_deg = values(P$aspect, mat = FALSE)[inpatch] * 180 / pi, forest_type = ft_lev[[2]][match(ft[inpatch], ft_lev[[1]])])
    pix_rows[[key]] <- pix
    pp <- st_as_sf(as.polygons(setValues(g, ifelse(inpatch, pv, NA)))); names(pp)[1] <- "patch"
    agg <- do.call(rbind, lapply(split(pix, pix$patch), function(d) data.frame(patch = d$patch[1], n_pixels = nrow(d), area_ha = nrow(d) * px_ha, mean_rbr = mean(d$rbr),
      dominant_class = SEV_SHORT[as.integer(names(which.max(table(factor(d$class_code, 1:3))))) + 1],
      low_ha = sum(d$class_code == 1) * px_ha, moderate_ha = sum(d$class_code == 2) * px_ha, high_ha = sum(d$class_code == 3) * px_ha,
      mean_elevation_m = mean(d$elevation_m), mean_slope_deg = mean(d$slope_deg), northness = mean(cos(d$aspect_deg * pi / 180)),
      dominant_aspect = names(which.max(table(aspect_class(d$aspect_deg)))),
      dominant_forest_type = { t <- table(d$forest_type); if (length(t)) names(which.max(t)) else NA_character_ })))
    pp <- merge(pp, agg, by = "patch"); pp$event_id <- e; pp$sensor <- s; pp$fire_date <- as.character(fd); pp$dzongkhag <- ev$dzongkhag
    pp$patch_id <- sprintf("%s_%s_p%03d", e, s, pp$patch); polys[[key]] <- pp; patch_rows[[key]] <- st_drop_geometry(pp)
  }
  win <- ext(buffer(P$pt, 1500)); if (length(keep_id)) win <- union(win, ext(trim(setValues(g, ifelse(inpatch, 1, NA)))))
  cls <- crop(setValues(g, sev), intersect(win, ext(g))); levels(cls) <- data.frame(value = 0:3, class = SEV_LEVELS)
  f <- file.path(DER, "severity_rasters", paste0(key, "_severity.tif"))
  writeRaster(cls, f, datatype = "INT1U", gdal = "COMPRESS=DEFLATE", overwrite = TRUE); cls_files[key] <- f
  tmpFiles(remove = TRUE)
  message(sprintf("%-28s %-14s offset %+.3f  patches %2d  mapped %6.2f ha (reported %s)", key, m$window_config, P$off, length(keep_id), m$mapped_area_ha, ev$reported_area_ha))
}
M <- do.call(rbind, lapply(metrics, function(x) { full <- names(metrics[[which.max(sapply(metrics, ncol))]]); for (n in setdiff(full, names(x))) x[[n]] <- NA; x[, full] }))
M <- M[M$status == "analysed", ]
P_ALL <- do.call(rbind, patch_rows); PX <- do.call(rbind, pix_rows); POLY <- do.call(rbind, polys)
Z <- do.call(rbind, zone_rows); RAD <- do.call(rbind, radius_rows)

# ---- 3. window-configuration sensitivity (same rule) --------------------------------------------------------------------------
WS <- list(); WAG <- list()
for (nm in names(WIN$sensitivity)) { cfg <- WIN$sensitivity[[nm]]
  for (k in seq_len(nrow(pairs))) { key <- paste(pairs$event_id[k], pairs$sensor[k], sep = "_")
    P <- prep(k, cfg); if (is.null(P) || !P$ok) { WS[[length(WS) + 1]] <- data.frame(config = nm, key = key, sensor = pairs$sensor[k], available = FALSE, detected = NA, area_ha = NA, high_share = NA); next }
    C <- candidates(P, Q_SEL); R <- apply_rule(P, C, MINHA_SEL, grow = TRUE)
    sv <- rep(NA_integer_, nrow(P$V)); sv[P$usable] <- 0L
    sv[R$inpatch] <- as.integer(cut(P$V$rbr[R$inpatch], c(-Inf, SV$rbr_low_moderate, SV$rbr_moderate_high, Inf), right = FALSE))
    WS[[length(WS) + 1]] <- data.frame(config = nm, key = key, sensor = pairs$sensor[k], available = TRUE, detected = length(R$keep_id) > 0,
                                       area_ha = sum(R$inpatch) * P$px_ha, high_share = if (any(R$inpatch)) mean(sv[R$inpatch] == 3) else NA)
    if (!is.null(vec_main[[key]])) { a <- vec_main[[key]] %in% 1:3; b <- sv %in% 1:3; both <- a & b
      WAG[[length(WAG) + 1]] <- data.frame(config = nm, key = key, union_px = sum(a | b), inter_px = sum(both), same_class_px = sum(vec_main[[key]][both] == sv[both])) } }
  tmpFiles(remove = TRUE); message("window sensitivity: ", nm) }
WS <- do.call(rbind, WS); WAG <- do.call(rbind, WAG)
WSUM <- do.call(rbind, lapply(split(WS, WS$config), function(d) { a <- d[d$available, ]; ag <- WAG[WAG$config == d$config[1], ]
  data.frame(config = d$config[1], pairs_available = nrow(a), detection = mean(a$detected), area_ha_sum = sum(a$area_ha), high_share = mean(a$high_share, na.rm = TRUE),
             jaccard_vs_main = sum(ag$inter_px) / max(1, sum(ag$union_px)), class_agreement_vs_main = sum(ag$same_class_px) / max(1, sum(ag$inter_px))) }))

# ---- 4. map per incident (Sentinel-2 when detected, else Landsat); sensor-specific maps ------------------------------------------
# Map per incident: season-matched pairs first (reviewer R1.1), then Sentinel-2 before Landsat; detected pairs preferred.
choose <- do.call(rbind, lapply(split(M, M$event_id), function(d) { d <- d[order(d$window_config != "season-matched", d$sensor != "sentinel"), ]
  hit <- d[d$detected, ]; if (nrow(hit)) hit[1, ] else d[1, ] }))
choose$map_status <- ifelse(choose$detected, "Mapped", "Not detected")
no_img <- setdiff(inc$event_id, M$event_id)
stat <- rbind(data.frame(event_id = choose$event_id, map_status = choose$map_status, sensor_used = ifelse(choose$detected, choose$sensor, NA)),
              data.frame(event_id = no_img, map_status = rep("No imagery", length(no_img)), sensor_used = rep(NA, length(no_img))))
inc_out <- merge(merge(inc, stat, by = "event_id"), choose[, c("event_id", "window_config", "mapped_area_ha", "low_ha", "moderate_ha", "high_ha", "mean_rbr", "n_patches", "thermal_evidence")], by = "event_id", all.x = TRUE)
CH <- choose[choose$detected, ]; key_ch <- paste(CH$event_id, CH$sensor, sep = "_")
POLY_CH <- POLY[paste(POLY$event_id, POLY$sensor, sep = "_") %in% key_ch, ]
P_CH <- P_ALL[paste(P_ALL$event_id, P_ALL$sensor, sep = "_") %in% key_ch, ]
PX_CH <- PX[paste(PX$event_id, PX$sensor, sep = "_") %in% key_ch, ]
both_ev <- intersect(M$event_id[M$sensor == "landsat"], M$event_id[M$sensor == "sentinel"])
SC <- do.call(rbind, lapply(both_ev, function(e) { a <- M[M$event_id == e & M$sensor == "landsat", ]; b <- M[M$event_id == e & M$sensor == "sentinel", ]
  pa <- POLY[POLY$event_id == e & POLY$sensor == "landsat", ]; pb <- POLY[POLY$event_id == e & POLY$sensor == "sentinel", ]
  jac <- if (nrow(pa) && nrow(pb)) { i <- suppressWarnings(st_area(st_intersection(st_union(pa), st_union(pb)))); u <- st_area(st_union(st_union(pa), st_union(pb)))
    as.numeric(sum(i)) / as.numeric(u) } else NA
  data.frame(event_id = e, landsat_detected = a$detected, sentinel_detected = b$detected, landsat_ha = a$mapped_area_ha, sentinel_ha = b$mapped_area_ha,
             landsat_high_share = a$high_ha / max(1e-9, a$mapped_area_ha), sentinel_high_share = b$high_ha / max(1e-9, b$mapped_area_ha), jaccard = jac) }))
agree <- mean(SC$landsat_detected == SC$sentinel_detected)

# ---- 5. atlas layers (20 m) -------------------------------------------------------------------------------------------------------
bv <- vect(study_buffer()); tmpl <- rast(ext(bv), resolution = 20, crs = CRS)
# Memory-light atlas: incident pieces stay on their own small windows (aligned to the 20 m template) and are combined
# with mosaic(); nothing is expanded to the full two-dzongkhag grid until the final extend().
build_atlas <- function(keys, years) {
  pc <- list(); pn <- list(); py <- list()
  for (i in seq_along(keys)) { cl <- rast(cls_files[keys[i]]); levels(cl) <- NULL; cl <- classify(cl, cbind(0, NA))
    piece <- project(cl, crop(tmpl, ext(cl) + 60, snap = "out"), method = "near")
    pc[[i]] <- piece; pn[[i]] <- ifel(!is.na(piece), 1, NA); py[[i]] <- ifel(!is.na(piece), years[i], NA) }
  mos <- function(L, f) extend(if (length(L) == 1) L[[1]] else mosaic(sprc(L), fun = f), tmpl)
  list(cls = mos(pc, "max"), n = mos(pn, "sum"), latest = mos(py, "max"), first = mos(py, "min")) }
yrs_ch <- as.integer(format(CH$fire_date, "%Y")); AT <- build_atlas(key_ch, yrs_ch)
for (nm in c("cls", "n", "latest", "first")) {
  r <- AT[[nm]]; if (nm == "cls") levels(r) <- data.frame(value = 1:3, class = SEV_LEVELS[-1])
  writeRaster(r, file.path(DER, c(cls = "atlas_highest_spectral_class_20m.tif", n = "atlas_times_mapped_20m.tif", latest = "atlas_latest_fire_year_20m.tif", first = "atlas_first_fire_year_20m.tif")[[nm]]),
              datatype = "INT2U", gdal = "COMPRESS=DEFLATE", overwrite = TRUE) }
cell_ha <- 0.04
atlas_area <- function(A, mask_v) {   # class counts via freq() on cropped, masked rasters (no full-grid value vectors)
  cl <- mask(crop(A$cls, mask_v), mask_v); nn <- mask(crop(A$n, mask_v), mask_v)
  f <- freq(cl); fr <- function(k) { x <- f$count[f$value == k]; if (length(x)) sum(x) else 0 }
  fn <- freq(nn); rep_ <- sum(fn$count[fn$value >= 2])
  c(unique_ha = sum(f$count) * cell_ha, low_ha = fr(1) * cell_ha, moderate_ha = fr(2) * cell_ha, high_ha = fr(3) * cell_ha, repeat_ha = rep_ * cell_ha) }
dzv <- study_dzongkhags(); AT_DZ <- do.call(rbind, lapply(seq_len(nrow(dzv)), function(i) data.frame(dzongkhag = dzv$dzongkhag[i], t(atlas_area(AT, vect(dzv[i, ]))))))
AT_TOT <- atlas_area(AT, vect(st_union(dzv)))
sensor_tot <- do.call(rbind, lapply(c("landsat", "sentinel"), function(s) { d <- M[M$sensor == s & M$detected, ]; ks <- paste(d$event_id, s, sep = "_")
  A <- build_atlas(ks, as.integer(format(d$fire_date, "%Y"))); a <- atlas_area(A, vect(st_union(dzv)))
  data.frame(map = paste0(c(landsat = "Landsat only", sentinel = "Sentinel-2 only")[[s]], " (", sum(M$sensor == s), " incidents imaged)"), incidents_mapped = nrow(d), t(a)) }))

# ---- 6. provisional area range across analysis choices ------------------------------------------------------------------------------
elig <- CAL[CAL$eligible, ]
rule_tot <- do.call(rbind, lapply(seq_len(nrow(elig)), function(j) { tot <- 0
  for (k in seq_len(nrow(pairs))) { key <- paste(pairs$event_id[k], pairs$sensor[k], sep = "_"); if (!key %in% key_ch) next
    P <- main_cfg(k); C <- candidates(P, elig$q[j]); R <- apply_rule(P, C, elig$min_ha[j], grow = TRUE); tot <- tot + sum(R$inpatch) * P$px_ha }
  data.frame(choice = sprintf("Rule q = %.3f, min %.2f ha", elig$q[j], elig$min_ha[j]), sum_ha = tot) }))
rad_tot <- aggregate(area_ha ~ radius_m, RAD[RAD$key %in% key_ch, ], sum)
win_tot <- do.call(rbind, lapply(names(WIN$sensitivity), function(nm) data.frame(choice = paste("Windows:", nm), sum_ha = sum(WS$area_ha[WS$config == nm & WS$key %in% key_ch], na.rm = TRUE))))
RANGE <- rbind(data.frame(choice = "Main analysis (sum of selected incident maps)", sum_ha = sum(CH$mapped_area_ha)),
               data.frame(choice = sensor_tot$map, sum_ha = sensor_tot$unique_ha), rule_tot,
               data.frame(choice = paste0("Search radius ", rad_tot$radius_m, " m"), sum_ha = rad_tot$area_ha), win_tot)
RANGE$note <- ifelse(grepl("only", RANGE$choice), "union over all incidents mapped by that sensor", "sum over the incidents of the main map")

# ---- 7. independent evaluation tables -------------------------------------------------------------------------------------------------
Z$band_label <- vapply(Z$band, function(b) sprintf("%.1f-%.1f km", band_rng(b)[1] / 1000, band_rng(b)[2] / 1000), "")
Z$set <- ifelse(Z$selection, "Selection zones", "Held-out zones")
ZS <- do.call(rbind, lapply(split(Z, list(Z$set, Z$band_label), drop = TRUE), function(d) { u <- d[!is.na(d$detected), ]; ci <- wilson_ci(sum(u$detected), nrow(u))
  data.frame(set = d$set[1], band = d$band_label[1], zones = nrow(u), detections = sum(u$detected), rate = mean(u$detected), low = ci[1], high = ci[2],
             zones_with_thermal = sum(u$thermal), detections_with_thermal = sum(u$detected & u$thermal),
             rate_without_thermal = sum(u$detected & !u$thermal) / max(1, sum(!u$thermal))) }))
held <- Z[!Z$selection & !is.na(Z$detected), ]; held_rate <- mean(held$detected); held_ci <- wilson_ci(sum(held$detected), nrow(held))
held_rate_nt <- sum(held$detected & !held$thermal) / sum(!held$thermal)
TV <- do.call(rbind, lapply(c(TRUE, FALSE), function(t) { d <- M[M$thermal_evidence == t, ]; ci <- wilson_ci(sum(d$detected), nrow(d))
  data.frame(thermal_evidence = ifelse(t, "Thermal evidence within 1 km", "No thermal evidence"), pairs = nrow(d), detected = sum(d$detected), rate = mean(d$detected), low = ci[1], high = ci[2]) }))
patch_thermal_share <- mean(M$thermal_in_patch[M$detected], na.rm = TRUE)

# ---- 8. Non-Forest composition and fuels / terrain models ----------------------------------------------------------------------------
dw_at <- function(d) { out <- rep(NA_integer_, nrow(d)); for (y in unique(d$fire_year)) { f <- file.path(VD, sprintf("dw_label_30m_%d.tif", y - 1)); if (!file.exists(f)) next
  s <- d$fire_year == y; out[s] <- extract(rast(f), as.matrix(d[s, c("x", "y")]))[, 1] }; out }
PX_CH$dw_prefire <- DWNAME[as.character(dw_at(PX_CH))]
PX_CH$worldcover <- WCNAME[as.character(extract(rast(file.path(VD, "worldcover2021_30m.tif")), as.matrix(PX_CH[, c("x", "y")]))[, 1])]
NF <- PX_CH[PX_CH$forest_type %in% "Non Forest", ]
NFT <- rbind(data.frame(source = "Dynamic World, year before the fire", as.data.frame(prop.table(table(class = NF$dw_prefire)))),
             data.frame(source = "ESA WorldCover 2021", as.data.frame(prop.table(table(class = NF$worldcover)))))
nf_share <- mean(PX_CH$forest_type %in% "Non Forest")
nf_grass_shrub <- with(NF, mean(dw_prefire %in% c("Grass", "Shrub and scrub"), na.rm = TRUE)); nf_trees <- with(NF, mean(dw_prefire %in% "Trees", na.rm = TRUE))
nf_crops_built <- with(NF, mean(dw_prefire %in% c("Crops", "Built", "Bare"), na.rm = TRUE))

# The fuel layer is RESTRICTED and not in the release zips: without it (e.g. on a workshop laptop) the fuel models
# and their figure are skipped and everything else runs.
FUEL_F <- tp("data/inputs/RESTRICTED/fuel_descriptors_2021_2022_100m_RESTRICTED_DERIVED.tif"); HAS_FUEL <- file.exists(FUEL_F)
PF <- st_drop_geometry(POLY_CH)[, c("patch_id", "event_id", "fire_date", "mean_rbr", "area_ha", "mean_slope_deg", "northness", "dominant_forest_type")]
if (HAS_FUEL) { fuel <- rast(FUEL_F)
  fv <- exactextractr::exact_extract(fuel, st_transform(POLY_CH, crs(fuel)), "mean", progress = FALSE); names(fv) <- names(fuel); PF <- cbind(PF, fv)
  write.csv(PF, file.path(DER, "RESTRICTED/patch_fuel_descriptors_RESTRICTED.csv"), row.names = FALSE)
} else message("Restricted fuel layer not found: fuel models skipped (all other analyses run).")
rownames(PF) <- NULL   # row i of PF = patch i of POLY_CH (centroids below)
PF$nonforest <- as.integer(PF$dominant_forest_type %in% "Non Forest"); PF$log_area <- log(PF$area_ha)
cen <- st_coordinates(st_centroid(st_geometry(POLY_CH)))
mm <- function(v, data = PF) { d <- data[is.finite(data[[v]]) & is.finite(data$mean_rbr), ]; d$z <- as.numeric(scale(d[[v]])); d$y <- as.numeric(scale(d$mean_rbr))
  f <- suppressMessages(lmer(y ~ z + scale(mean_slope_deg) + northness + log_area + nonforest + (1 | event_id), data = d, REML = TRUE))
  co <- summary(f)$coefficients["z", ]; ci <- co[1] + c(-1.96, 1.96) * co[2]
  data.frame(descriptor = v, n_patches = nrow(d), n_fires = length(unique(d$event_id)), std_coef = co[1], ci_low = ci[1], ci_high = ci[2], t_value = co[3],
             spearman = suppressWarnings(cor(d[[v]], d$mean_rbr, method = "spearman")), singular = isSingular(f)) }
FM <- NULL; shrub_post <- NULL; post_fuel <- PF[0, ]
# Mixed models need enough fires and patches; with too few (e.g. workshop quick mode) they are skipped with a message.
safe <- function(expr, what) tryCatch(expr, error = function(e) { message(what, " skipped: ", conditionMessage(e)); NULL })
if (HAS_FUEL) { FM <- safe({ x <- do.call(rbind, lapply(names(fuel), mm)); x$p_wald <- 2 * pnorm(-abs(x$t_value)); x$p_bh <- p.adjust(x$p_wald, "BH"); x }, "Fuel models")
  post_fuel <- PF[as.Date(PF$fire_date) >= as.Date("2022-06-01"), ]
  shrub_post <- if (nrow(post_fuel) >= 6) suppressWarnings(cor.test(post_fuel$shrub_cover_pct, post_fuel$mean_rbr, method = "spearman", exact = FALSE)) else NULL }
tm <- safe(suppressMessages(lmer(scale(mean_rbr) ~ northness + scale(mean_slope_deg) + (1 | event_id), data = PF)), "Terrain model")
TMc <- if (!is.null(tm)) summary(tm)$coefficients else matrix(NA, 1, 3, dimnames = list("model not estimable", c("Estimate", "Std. Error", "t value")))
res_f <- safe(residuals(suppressMessages(lmer(as.formula(paste("scale(mean_rbr) ~", if (HAS_FUEL) "scale(shrub_cover_pct) +" else "", "scale(mean_slope_deg) + northness + log_area + nonforest + (1 | event_id)")), data = PF))), "Residual model")
moran <- if (is.null(res_f)) NULL else tryCatch(moran.test(res_f, nb2listw(knn2nb(knearneigh(cen[as.integer(names(res_f)), , drop = FALSE], k = 4)), style = "W")), error = function(e) { message("Moran test failed: ", conditionMessage(e)); NULL })

# ---- 9. spatial products and tables --------------------------------------------------------------------------------------------------
gpkg <- file.path(DER, "burn_severity_paro_thimphu.gpkg"); if (file.exists(gpkg)) file.remove(gpkg)
st_write(POLY_CH[, c("patch_id", "event_id", "sensor", "fire_date", "dzongkhag", "area_ha", "low_ha", "moderate_ha", "high_ha", "mean_rbr", "dominant_class",
                     "dominant_forest_type", "dominant_aspect", "northness", "mean_elevation_m", "mean_slope_deg")], gpkg, "burned_patches_selected", quiet = TRUE)
st_write(POLY[, c("patch_id", "event_id", "sensor", "fire_date", "area_ha", "mean_rbr", "dominant_class")], gpkg, "burned_patches_all_sensors", quiet = TRUE, append = TRUE)
ip <- st_transform(st_as_sf(inc_out, coords = c("longitude", "latitude"), crs = 4326, remove = FALSE), CRS); st_write(ip, gpkg, "incident_points", quiet = TRUE, append = TRUE)
zs <- st_as_sf(Z, coords = c("cx", "cy"), crs = CRS); st_write(zs[, c("key", "sensor", "band_label", "set", "detected", "thermal")], gpkg, "placebo_zones", quiet = TRUE, append = TRUE)
write.csv(M, file.path(DER, "incident_sensor_metrics.csv"), row.names = FALSE); write.csv(inc_out, file.path(DER, "incident_severity_summary.csv"), row.names = FALSE)
write.csv(WS, file.path(DER, "window_sensitivity_by_pair.csv"), row.names = FALSE); write.csv(RAD, file.path(DER, "search_radius_sensitivity.csv"), row.names = FALSE)

# ============================================================
# DATA HEALTH
# ============================================================
data_health(run, M[, c("sensor", "window_config", "resolution_m", "pre_images", "post_images", "ring_offset_dnbr", "ring_iqr_dnbr", "inner_usable_share", "inner_shadow_share",
                       "thermal_evidence", "detected", "mapped_area_ha", "reported_area_ha")], "Incident x sensor metrics (main configuration)")
data_health(run, P_CH[, c("area_ha", "mean_rbr", "dominant_class", "mean_slope_deg", "northness", "dominant_forest_type")], "Burned patches (selected sensor per incident)")
data_health(run, WSUM, "Window-configuration sensitivity summary")
rbr_ub <- SV$unburned_low_dnbr_x1000 / (median(PX_CH$pre_nbr) + 1.001)
n_fb <- sum(M$window_config != "season-matched")
write_health(run, notes = c(
  sprintf("%d incidents in Paro and Thimphu have valid coordinates and dates (fires %s to %s); %d have composites (%d incident-sensor pairs); %d lack imagery (excluded from the parent download for quality flags).",
          nrow(inc), min(inc$start_date_local), max(inc$start_date_local), length(unique(M$event_id)), nrow(M), length(no_img)),
  sprintf("Main windows: season-matched pre-fire (same 90 days one year earlier) vs 90-day post-fire; %d pairs fell back to the adjacent 90-day pre window because no season-matched composite exists (Sentinel-2 before 2017-03-28 or no clear image).", n_fb),
  sprintf("Detection rule chosen on %d selection placebo zones; %d held-out zones in three distance bands evaluate it.", sum(Z$selection & !is.na(Z$detected)), nrow(held)),
  sprintf("Spectral-change classes use Parks et al. (2018) RBR breaks 116/283; FIREMON dNBR 100 corresponds to RBR %.0f at the median pre-fire NBR (%.2f). Classes are provisional and not ecological severity.", rbr_ub, median(PX_CH$pre_nbr)),
  sprintf("%d incident-sensor pairs have a later DoFPS incident within 5.5 km inside their post-fire window (possible contamination; listed in process data).", sum(M$later_incidents_in_post_window > 0)),
  "Statistical units: incident-sensor pairs for detection, placebo zones for background detection, burned patches with fire identity as random effect for fuel and terrain models; pixel distributions are descriptive only.",
  "Session time zone is set to Asia/Thimphu (UTC+6)."))

# ============================================================
# FIGURES
# ============================================================
dz <- study_dzongkhags(); gw <- study_gewogs()
n_map <- sum(stat$map_status == "Mapped"); n_ana <- nrow(choose)
ipf <- ip; ipf$map_status <- factor(ipf$map_status, c("Mapped", "Not detected", "No imagery"))
p <- ggplot() + geom_sf(data = gw, fill = NA, colour = "#cccccc", linewidth = 0.2) + geom_sf(data = dz, fill = NA, colour = "black", linewidth = 0.5) +
  geom_sf(data = ipf, aes(shape = map_status, size = pmax(reported_area_ha, 0.1))) +
  scale_shape_manual(values = c(Mapped = 16, `Not detected` = 1, `No imagery` = 4), name = "Satellite result") + scale_size_area(max_size = 5, breaks = c(1, 10, 100), name = "Reported area (ha)") +
  geom_sf_text(data = dz, aes(label = dzongkhag), family = SCI$font, size = 3.2, nudge_y = 9000) +
  ggspatial::annotation_scale(location = "bl", text_family = SCI$font, height = unit(0.15, "cm")) + theme_sci_map() + theme(legend.position = "right")
save_fig(run, p, 1, "incident_overview", st_drop_geometry(ipf)[, c("event_id", "dzongkhag", "report_year", "reported_area_ha", "map_status", "sensor_used")], c(
  sprintf("DoFPS fire incidents in Paro and Thimphu (%s to %s) by satellite detection outcome (n = %d incidents with valid coordinates).", min(inc$start_date_local), max(inc$start_date_local), nrow(inc)),
  "Filled circles: burned patches mapped; open circles: imagery analysed, no patch passing the detection rule within 500 m; crosses: no composites; symbol size scales with DoFPS reported area.",
  sprintf("%d of %d imaged incidents (%.0f%%) were mapped, so satellite detection covers part of the reported fire activity and does not replace field perimeters.", n_map, n_ana, 100 * n_map / n_ana)), size = c(7.2, 5.6))

top <- head(CH[order(-CH$mapped_area_ha), ], 6)
mk <- function(i) { r <- rast(cls_files[paste(top$event_id[i], top$sensor[i], sep = "_")]); pp <- POLY_CH[POLY_CH$event_id == top$event_id[i], ]
  pr <- st_coordinates(pts[pts$event_id == top$event_id[i], ]); e0 <- union(ext(vect(pp)), ext(pr[1] - 1, pr[1] + 1, pr[2] - 1, pr[2] + 1))
  cx <- mean(c(e0$xmin, e0$xmax)); cy <- mean(c(e0$ymin, e0$ymax)); h <- max(e0$xmax - e0$xmin, e0$ymax - e0$ymin) / 2 + 250
  d <- as.data.frame(crop(r, ext(cx - h, cx + h, cy - h, cy + h)), xy = TRUE, na.rm = TRUE); names(d)[3] <- "cl"; d$cl <- factor(as.character(d$cl), SEV_LEVELS)
  d$lab <- sprintf("%s, %s, %s\nmapped %.0f ha | reported %s ha", sub("^DOFPS_", "", top$event_id[i]), format(top$fire_date[i], "%b %Y"),
                   ifelse(top$sensor[i] == "sentinel", "S2", "Landsat"), top$mapped_area_ha[i], smart_format(top$reported_area_ha[i]))
  ggplot(d, aes(x, y, fill = cl)) + geom_raster() + scale_fill_manual(values = SEV_COLS, drop = FALSE, name = "Spectral-change class (provisional)") +
    annotate("point", x = pr[1], y = pr[2], shape = 3, size = 2.5, stroke = 0.8) + facet_wrap(~ lab) + coord_equal(xlim = c(cx - h, cx + h), ylim = c(cy - h, cy + h), expand = FALSE) +
    ggspatial::annotation_scale(location = "bl", text_family = SCI$font, height = unit(0.1, "cm"), text_cex = 0.6) + theme_sci_map(8) + theme(legend.position = if (i == 1) "bottom" else "none") }
p <- wrap_plots(lapply(seq_len(nrow(top)), mk), ncol = 3) + plot_layout(guides = "collect") + plot_annotation(theme = theme(legend.position = "bottom"))
save_fig(run, p, 2, "change_maps_top6", top[, c("event_id", "sensor", "fire_date", "mapped_area_ha", "low_ha", "moderate_ha", "high_ha", "reported_area_ha")], c(
  "Provisional spectral-change classes of the six largest mapped DoFPS incidents in Paro and Thimphu.",
  sprintf("Offset-corrected RBR from season-matched composites, classes Low < %d <= Moderate < %d <= High (Parks et al. 2018 breaks, not calibrated for Bhutan), inside patches detected within 500 m and grown into connected margins; grey = no detected change; cross = reported point.", SV$rbr_low_moderate, SV$rbr_moderate_high),
  sprintf("The high spectral-change class covers %.0f%% of these patches; whether it corresponds to high ecological severity can only be established with the planned CBI plots.", 100 * sum(top$high_ha) / sum(top$mapped_area_ha))), size = c(7.2, 6.2))

pc <- ggplot(CAL, aes(placebo_selection, detection)) + geom_vline(xintercept = SV$max_placebo_rate, linetype = "dashed") + geom_path(aes(group = factor(q)), colour = "#bbbbbb", linewidth = 0.4) +
  geom_point(aes(shape = factor(sprintf("%.1f", 100 * q))), size = 2) + ggrepel::geom_text_repel(aes(label = paste0(min_ha, " ha")), size = 2.3, family = SCI$font, min.segment.length = 0.3, segment.size = 0.2, seed = 1) +
  annotate("point", x = best$placebo_selection, y = best$detection, shape = 1, size = 6, stroke = 0.8) + scale_shape_manual(values = c(16, 17, 15, 1), name = "Ring percentile") +
  scale_x_continuous(labels = scales::percent) + scale_y_continuous(labels = scales::percent) + labs(x = "Detections in selection placebo zones (%)", y = "Detections at reported incidents (%)") +
  theme_sci() + theme(legend.position = "bottom")
save_fig(run, pc, 3, "rule_selection", CAL, c(
  sprintf("Selection of the detection rule on selection placebo zones only (%d zones, %.1f-%.1f km from reported points).", sum(Z$selection & !is.na(Z$detected)),
          band_rng(PL$selection_band)[1] / 1000, band_rng(PL$selection_band)[2] / 1000),
  sprintf("Settings combine the ring-noise percentile with the minimum patch area (labels); the dashed line is the %.0f%% ceiling; the circled rule is used throughout; held-out zones are not used here.", 100 * SV$max_placebo_rate),
  sprintf("The selected rule (%.1f percentile, >= %s ha) detects %.0f%% of imaged incident-sensor pairs at %.1f%% background detection in the selection zones; its independent evaluation follows in the next figure.",
          100 * Q_SEL, MINHA_SEL, 100 * best$detection, 100 * best$placebo_selection)), size = c(5.5, 4.2))

ZB <- ZS[ZS$set == "Held-out zones", ]
pa <- ggplot(ZB, aes(band, rate)) + geom_col(fill = "#bbbbbb", colour = "black", linewidth = 0.25, width = 0.6) + geom_errorbar(aes(ymin = low, ymax = high), width = 0.2, linewidth = 0.4) +
  geom_point(aes(y = rate_without_thermal), shape = 4, size = 2.5) + geom_text(aes(y = high, label = paste0("n=", zones)), vjust = -0.4, size = 2.6, family = SCI$font) +
  scale_y_continuous(labels = scales::percent, limits = c(0, max(0.3, max(ZB$high) + 0.05))) + labs(x = "Held-out placebo zones: distance from report", y = "Background detection (%)") + theme_sci()
pb <- ggplot(TV, aes(thermal_evidence, rate)) + geom_col(fill = "#555555", colour = "black", linewidth = 0.25, width = 0.6) + geom_errorbar(aes(ymin = low, ymax = high), width = 0.2, linewidth = 0.4) +
  geom_text(aes(y = high, label = paste0("n=", pairs)), vjust = -0.4, size = 2.6, family = SCI$font) + scale_y_continuous(labels = scales::percent, limits = c(0, 1.08)) +
  labs(x = NULL, y = "Incident-sensor pairs detected (%)") + theme_sci() + theme(axis.text.x = element_text(size = 8))
p <- pa + pb + plot_annotation(tag_levels = "a", tag_prefix = "(", tag_suffix = ")") & theme(plot.tag = element_text(family = SCI$font, size = 10))
save_fig(run, p, 4, "independent_evaluation", rbind(cbind(panel = "a", ZB[, c("band", "zones", "detections", "rate", "low", "high", "rate_without_thermal")] |> setNames(c("group", "n", "k", "rate", "low", "high", "extra"))),
                                                      cbind(panel = "b", TV[, c("thermal_evidence", "pairs", "detected", "rate", "low", "high")] |> transform(extra = NA) |> setNames(c("group", "n", "k", "rate", "low", "high", "extra")))), c(
  "Independent evaluation of the detection rule: (a) background detection in held-out placebo zones by distance from the reported point; (b) detection of incident-sensor pairs with and without independent thermal evidence (FIRMS active fire or MODIS MCD64A1 burned pixels within 1 km, 10 days before to 30 days after the reported date).",
  "Bars: rates with Wilson 95% CI; crosses in (a): rate after removing zones that themselves contain thermal evidence. Placebo zones are not verified fire-free, so (a) is a background-detection rate, not a false-positive rate; thermal products miss small surface fires, so (b) is a partial reference.",
  sprintf("Held-out background detection is %.1f%% (95%% CI %.1f-%.1f%%) against %.1f%% in the selection zones, and %.0f%% of pairs with thermal evidence are detected against %.0f%% without, so the rule generalises beyond the zones used to choose it and finds most thermally confirmed fires.",
          100 * held_rate, 100 * held_ci[1], 100 * held_ci[2], 100 * best$placebo_selection, 100 * TV$rate[1], 100 * TV$rate[2])), size = c(7.2, 3.8))

M$area_class <- cut(M$reported_area_ha, c(-Inf, 1, 10, Inf), labels = c("< 1 ha", "1-10 ha", ">= 10 ha"))
d5 <- do.call(rbind, lapply(split(M, list(M$sensor, M$area_class), drop = TRUE), function(d) { ci <- wilson_ci(sum(d$detected), nrow(d))
  data.frame(sensor = d$sensor[1], area_class = d$area_class[1], n = nrow(d), detected = sum(d$detected), share = mean(d$detected), low = ci[1], high = ci[2]) }))
lt <- glm(detected ~ log10(reported_area_ha) + sensor, binomial, data = M); co <- summary(lt)$coefficients; or10 <- exp(co["log10(reported_area_ha)", "Estimate"])
p <- ggplot(d5, aes(area_class, share, fill = sensor)) + annotate("rect", xmin = -Inf, xmax = Inf, ymin = held_ci[1], ymax = held_ci[2], fill = "#eeeeee") + geom_hline(yintercept = held_rate, linetype = "dashed") +
  geom_col(position = position_dodge(0.7), width = 0.65, colour = "black", linewidth = 0.25) + geom_errorbar(aes(ymin = low, ymax = high), position = position_dodge(0.7), width = 0.2, linewidth = 0.4) +
  geom_text(aes(y = high, label = paste0("n=", n)), position = position_dodge(0.7), vjust = -0.4, size = 2.8, family = SCI$font) +
  scale_fill_manual(values = c(landsat = "#bbbbbb", sentinel = "#555555"), labels = c(landsat = "Landsat (30 m)", sentinel = "Sentinel-2 (20 m)"), name = NULL) +
  scale_y_continuous(labels = scales::percent, limits = c(0, 1.08)) + labs(x = "DoFPS reported burned area", y = "Pairs with mapped patches (%)") + theme_sci() + theme(legend.position = "bottom")
save_fig(run, p, 5, "detection_by_area_sensor", d5, c(
  "Detection of DoFPS incidents in Paro and Thimphu by reported area and sensor.",
  sprintf("Shares with Wilson 95%% CI; dashed line and band: held-out background-detection rate (%.1f%%); logistic regression on log10 reported area and sensor: odds ratio %.2f per tenfold area (%s), sensor %s.",
          100 * held_rate, or10, format_p(co["log10(reported_area_ha)", "Pr(>|z|)"]), format_p(co["sensorsentinel", "Pr(>|z|)"])),
  sprintf("Detection rises from %.0f%% for incidents reported under 1 ha to %.0f%% for 10 ha or more, so 20-30 m composites are dependable only for the larger fires.",
          100 * mean(M$detected[M$area_class == "< 1 ha"]), 100 * mean(M$detected[M$area_class == ">= 10 ha"]))), size = c(5.5, 3.8))

RADS <- do.call(rbind, lapply(split(RAD, RAD$radius_m), function(d) data.frame(radius_m = d$radius_m[1], detection = mean(d$detected), area_ha = sum(d$area_ha[d$key %in% key_ch]))))
pa <- ggplot(RADS, aes(radius_m, detection)) + geom_line() + geom_point(size = 2) + scale_x_continuous(breaks = SV$search_radius_test_m) + scale_y_continuous(labels = scales::percent) +
  labs(x = "Search radius (m)", y = "Pairs detected (%)") + theme_sci()
pb <- ggplot(RADS, aes(radius_m, area_ha)) + geom_line() + geom_point(size = 2) + scale_x_continuous(breaks = SV$search_radius_test_m) + labs(x = "Search radius (m)", y = "Mapped area, main incidents (ha)") + theme_sci()
p <- pa + pb + plot_annotation(tag_levels = "a", tag_prefix = "(", tag_suffix = ")") & theme(plot.tag = element_text(family = SCI$font, size = 10))
save_fig(run, p, 6, "search_radius_sensitivity", RADS, c(
  "Sensitivity of (a) detection and (b) mapped area to the search radius around DoFPS reported points.",
  "Same rule and composites; a patch counts when any of its pixels lies within the radius; mapped area summed over the incidents of the main map.",
  sprintf("Detection changes from %.0f%% at 100 m to %.0f%% at 1,000 m and mapped area from %.0f to %.0f ha, so coordinate accuracy matters and the 500 m radius is a compromise rather than a perimeter.",
          100 * RADS$detection[1], 100 * tail(RADS$detection, 1), RADS$area_ha[1], tail(RADS$area_ha, 1))), size = c(7.2, 3.4))

WSUM$config <- factor(WSUM$config, names(WIN$sensitivity))
pa <- ggplot(WSUM, aes(config, detection)) + geom_col(fill = "#bbbbbb", colour = "black", linewidth = 0.25, width = 0.6) + geom_text(aes(label = paste0("n=", pairs_available)), vjust = -0.4, size = 2.5, family = SCI$font) +
  scale_y_continuous(labels = scales::percent, limits = c(0, 1)) + labs(x = NULL, y = "Pairs detected (%)") + theme_sci() + theme(axis.text.x = element_text(angle = 25, hjust = 1, size = 7))
pb <- ggplot(WSUM, aes(config, jaccard_vs_main)) + geom_col(fill = "#555555", colour = "black", linewidth = 0.25, width = 0.6) + geom_point(aes(y = class_agreement_vs_main), shape = 4, size = 2.5) +
  scale_y_continuous(labels = scales::percent, limits = c(0, 1)) + labs(x = NULL, y = "Agreement with main map (%)") + theme_sci() + theme(axis.text.x = element_text(angle = 25, hjust = 1, size = 7))
p <- pa + pb + plot_annotation(tag_levels = "a", tag_prefix = "(", tag_suffix = ")") & theme(plot.tag = element_text(family = SCI$font, size = 10))
v10 <- WSUM[WSUM$config == names(WIN$sensitivity)[1], ]; ext_ <- WSUM[grepl("extended", WSUM$config), ]
save_fig(run, p, 7, "window_sensitivity", WSUM, c(
  "Sensitivity of detection and mapped patches to the pre- and post-fire compositing windows, Paro and Thimphu.",
  "Same detection rule throughout; (a) share of available incident-sensor pairs detected; (b) bars: Jaccard overlap of mapped patches with the main map (season-matched pre vs 90-day post), crosses: share of overlapping pixels in the same spectral-change class.",
  sprintf("The v1.0 adjacent windows reproduce %.0f%% of the main patches (Jaccard) and the extended assessment %.0f%%, so window choice changes the mapped geometry materially and season-matched windows are needed for comparable estimates.",
          100 * v10$jaccard_vs_main, 100 * ext_$jaccard_vs_main)), size = c(7.2, 4))

pa <- ggplot(M[M$detected & M$reported_area_ha > 0, ], aes(reported_area_ha, mapped_area_ha, shape = sensor)) + geom_abline(slope = 1, intercept = 0, linetype = "dashed") + geom_point(size = 1.8) +
  scale_shape_manual(values = c(landsat = 1, sentinel = 16), labels = c(landsat = "Landsat", sentinel = "Sentinel-2"), name = NULL) + scale_x_log10() + scale_y_log10() +
  labs(x = "DoFPS reported area (ha)", y = "Mapped area (ha)") + theme_sci() + theme(legend.position = "bottom")
SCb <- SC[SC$landsat_detected & SC$sentinel_detected, ]
pb <- ggplot(SCb, aes(landsat_ha, sentinel_ha)) + geom_abline(slope = 1, intercept = 0, linetype = "dashed") + geom_point(size = 1.8) + scale_x_log10() + scale_y_log10() +
  labs(x = "Landsat mapped area (ha)", y = "Sentinel-2 mapped area (ha)") + theme_sci()
p <- pa + pb + plot_annotation(tag_levels = "a", tag_prefix = "(", tag_suffix = ")") & theme(plot.tag = element_text(family = SCI$font, size = 10))
d4 <- M[M$detected & M$reported_area_ha > 0, ]; sp <- cor.test(d4$mapped_area_ha, d4$reported_area_ha, method = "spearman", exact = FALSE)
save_fig(run, p, 8, "area_agreement", rbind(data.frame(panel = "a", x = d4$reported_area_ha, y = d4$mapped_area_ha), data.frame(panel = "b", x = SCb$landsat_ha, y = SCb$sentinel_ha)), c(
  "Agreement of mapped area (a) with DoFPS reported area and (b) between Landsat and Sentinel-2 for incidents detected by both sensors.",
  sprintf("Log-log axes, dashed 1:1 lines; (a) Spearman rho = %.2f (%s); (b) n = %d incidents, median Jaccard overlap of patches %.2f, detection agreement %.0f%% of %d incidents imaged by both.",
          sp$estimate, format_p(sp$p.value), nrow(SCb), median(SCb$jaccard, na.rm = TRUE), 100 * agree, nrow(SC)),
  sprintf("Mapped areas rank fires like reported areas, but the two sensors map the same fire with a median patch overlap of only %.0f%%, so sensor-specific estimates are reported separately and the combined total is provisional.", 100 * median(SCb$jaccard, na.rm = TRUE))), size = c(7.2, 3.8))

nfp <- NFT; nfp$class <- factor(nfp$class, unique(nfp$class[order(-nfp$Freq)]))
p <- ggplot(nfp, aes(Freq, class)) + geom_col(fill = "#888888", colour = "black", linewidth = 0.2, width = 0.65) + facet_wrap(~ source, scales = "free_y") +
  scale_x_continuous(labels = scales::percent) + labs(x = "Share of burned pixels mapped as Non Forest (%)", y = NULL) + theme_sci()
save_fig(run, p, 9, "nonforest_composition", NFT, c(
  sprintf("Land cover of burned pixels that the DoFPS forest-type map labels Non Forest (%.0f%% of all mapped burned pixels), Paro and Thimphu.", 100 * nf_share),
  "Dynamic World annual label (mode) of the calendar year before each fire, and ESA WorldCover 2021, at 30 m; WorldCover postdates some fires.",
  sprintf("Before the fires, %.0f%% of these pixels were grass or shrub and scrub, %.0f%% trees and %.0f%% crops, built or bare, so the Non Forest class mixes open wildland, tree cover missed by the forest-type map and some non-wildland land.",
          100 * nf_grass_shrub, 100 * nf_trees, 100 * nf_crops_built)), size = c(7.2, 3.6))

IX <- PX_CH[, c("pre_nbr", "rbr", "rdnbr")]; IX$pre_bin <- cut(IX$pre_nbr, c(-Inf, 0.1, 0.2, 0.3, 0.4, 0.5, Inf), labels = c("< 0.1", "0.1-0.2", "0.2-0.3", "0.3-0.4", "0.4-0.5", ">= 0.5"))
d6 <- rbind(data.frame(pre_bin = IX$pre_bin, index = "RBR", rel = IX$rbr / SV$rbr_moderate_high), data.frame(pre_bin = IX$pre_bin, index = "RdNBR", rel = IX$rdnbr / 512)); d6 <- d6[is.finite(d6$rel), ]
s6 <- do.call(data.frame, aggregate(rel ~ pre_bin + index, d6, function(x) c(med = median(x), iqr = IQR(x))))
p <- ggplot(d6, aes(pre_bin, rel, fill = index)) + geom_hline(yintercept = 1, linetype = "dashed") + geom_boxplot(outlier.shape = NA, width = 0.6, linewidth = 0.35, position = position_dodge(0.7)) +
  scale_fill_manual(values = c(RBR = "#ffffff", RdNBR = "#888888"), name = NULL) + coord_cartesian(ylim = quantile(d6$rel, c(.01, .99))) +
  labs(x = "Pre-fire NBR", y = "Index / its moderate-high break (ratio)") + theme_sci() + theme(legend.position = "bottom")
iq <- function(i, b) s6$rel.iqr[s6$index == i & s6$pre_bin == b]
save_fig(run, p, 10, "rbr_vs_rdnbr", s6, c(
  sprintf("RBR and RdNBR of mapped burned pixels across pre-fire NBR, Paro and Thimphu (n = %s pixels; descriptive, pixels are not independent).", format(nrow(IX), big.mark = ",")),
  "Each index divided by its moderate/high break (RBR 283, RdNBR 512; Parks et al. 2018); boxes median and IQR, whiskers 1.5 IQR, y-axis trimmed to the 1st-99th percentile.",
  sprintf("Below pre-fire NBR 0.1 the spread of RdNBR is %.1f times that of RBR, so RdNBR inflates change where pre-fire vegetation is sparse and RBR is the safer index.", iq("RdNBR", "< 0.1") / iq("RBR", "< 0.1"))), size = c(5.5, 3.8))

if (!is.null(FM)) {
FMp <- FM; FMp$descriptor <- factor(FMp$descriptor, FMp$descriptor[order(FMp$std_coef)])
p <- ggplot(FMp, aes(std_coef, descriptor)) + geom_vline(xintercept = 0, linetype = "dashed") + geom_errorbar(aes(xmin = ci_low, xmax = ci_high), width = 0.25, linewidth = 0.4, orientation = "y") +
  geom_point(size = 2) + labs(x = "Standardised effect on patch mean RBR (95% CI)", y = NULL) + theme_sci()
sh <- FM[FM$descriptor == "shrub_cover_pct", ]
save_fig(run, p, 11, "fuel_models", FM, c(
  sprintf("Exploratory association between mapped fuel descriptors (2021-2022, 100 m) and patch mean RBR, Paro and Thimphu (%d patches from %d fires).", max(FM$n_patches), max(FM$n_fires)),
  "Linear mixed models, one descriptor at a time, standardised, adjusted for slope, northness, log patch area and Non Forest dominance, with fire identity as random intercept; Wald 95% CI; Benjamini-Hochberg adjustment across descriptors.",
  sprintf("Shrub cover has a standardised effect of %.2f (95%% CI %.2f to %.2f, adjusted %s)%s; fuel maps postdate some fires, so this remains an exploratory, non-causal association.",
          sh$std_coef, sh$ci_low, sh$ci_high, format_p(sh$p_bh), if (!is.null(shrub_post)) sprintf(" and Spearman rho %.2f among the %d patches of fires after mid-2022", shrub_post$estimate, nrow(post_fuel)) else "")), size = c(5.5, 3.6))
}

# ---- process data and results ---------------------------------------------------------------------------------------------------------
write_process(run, CAL, "rule_selection_and_heldout")
write_process(run, ZS, "placebo_by_band_and_set")
write_process(run, TV, "thermal_evaluation")
write_process(run, M[, c("event_id", "sensor", "window_config", "fire_date", "pre_window", "pre_images", "pre_dates", "post_window", "post_images", "post_dates",
                         "later_incidents_in_post_window", "inner_usable_share", "inner_shadow_share", "inner_nonveg_share", "ring_offset_dnbr", "thermal_firms", "thermal_mcd",
                         "detected", "mapped_area_ha")], "composites_masks_by_incident")
write_process(run, inc_out[, setdiff(names(inc_out), c("village", "locality"))], "incident_summary")
write_process(run, P_CH, "burned_patches_selected")
write_process(run, SC, "sensor_comparison")
write_process(run, sensor_tot, "sensor_specific_atlas_totals")
write_process(run, AT_DZ, "atlas_by_dzongkhag")
write_process(run, RANGE, "provisional_area_range")
write_process(run, WSUM, "window_sensitivity")
write_process(run, NFT, "nonforest_composition")
if (!is.null(FM)) write_process(run, FM, "fuel_mixed_models")
write_process(run, data.frame(term = rownames(TMc), TMc, row.names = NULL), "terrain_mixed_model")
write_process(run, data.frame(parameter = names(unlist(SV)), value = as.character(unlist(SV))), "parameters")
ty <- aggregate(cbind(mapped_area_ha, low_ha, moderate_ha, high_ha) ~ report_year, CH, sum)
res <- list(title = TITLE, years = yrs, incidents_total = nrow(inc), incidents_imaged = length(unique(M$event_id)), pairs = nrow(M), incidents_no_imagery = no_img,
            fallback_pairs = n_fb, incidents_mapped = n_map, rule_q = Q_SEL, rule_min_ha = MINHA_SEL, detection_all = best$detection,
            placebo_selection = best$placebo_selection, placebo_heldout = held_rate, placebo_heldout_ci = as.numeric(held_ci), placebo_heldout_no_thermal = held_rate_nt,
            placebo_bands = ZS, thermal = TV, patch_thermal_share = patch_thermal_share, detection_lt1 = mean(M$detected[M$area_class == "< 1 ha"]),
            detection_ge10 = mean(M$detected[M$area_class == ">= 10 ha"]), odds_ratio = or10, sensor_agreement = agree, n_both = nrow(SC),
            sensor_jaccard_median = median(SCb$jaccard, na.rm = TRUE), spearman_area = unname(sp$estimate), spearman_p = sp$p.value,
            median_mapped_to_reported = median(d4$mapped_area_ha / d4$reported_area_ha), atlas_total = as.list(AT_TOT), atlas_by_dzongkhag = AT_DZ,
            sensor_totals = sensor_tot, area_range = RANGE, area_range_min = min(RANGE$sum_ha), area_range_max = max(RANGE$sum_ha),
            sum_incident_maps = sum(CH$mapped_area_ha), by_year = ty, radius = RADS, windows = WSUM, nonforest_share = nf_share, nonforest_composition = NFT,
            nf_grass_shrub = nf_grass_shrub, nf_trees = nf_trees, nf_crops_built = nf_crops_built, fuel_models = FM,
            shrub_post2022 = if (!is.null(shrub_post)) list(rho = unname(shrub_post$estimate), p = shrub_post$p.value, n = nrow(post_fuel)) else NULL,
            terrain = data.frame(term = rownames(TMc), TMc, row.names = NULL), moran_p = if (!is.null(moran)) moran$p.value else NA,
            rdnbr_rbr_iqr_ratio = iq("RdNBR", "< 0.1") / iq("RBR", "< 0.1"), rbr_ub_equivalent = rbr_ub, median_ring_offset = median(M$ring_offset_dnbr),
            later_incident_pairs = sum(M$later_incidents_in_post_window > 0), median_shadow = median(M$inner_shadow_share))
write_json_pretty(res, file.path(DER, "results_severity.json"))
build_report(run, intro = c(
  sprintf("Satellite detection and provisional spectral-change mapping of DoFPS incidents in Paro and Thimphu (%d-%d): %d of %d imaged incidents mapped; provisional unique mapped area %.0f ha (range across analysis choices %.0f-%.0f ha).",
          yrs[1], yrs[2], n_map, n_ana, AT_TOT[["unique_ha"]], min(RANGE$sum_ha), max(RANGE$sum_ha)),
  "Classes are spectral-change classes from provisional RBR breaks; detection was selected on half of the placebo zones and evaluated on held-out zones and independent thermal evidence. Not a validated burn-severity product."))
print(WSUM); print(TV); print(ZS)
unlink(TMPD, recursive = TRUE)
