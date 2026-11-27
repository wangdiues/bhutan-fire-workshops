# 15  Fire-line siting (5 km) and prescribed-burn site selection (7 sites, 24-26 ha) for the Thimphu WUI
# Criteria: docs/Criteria for firelines and prescribed burning.docx (DoFPS, refined 2026-11-26). Mandatory exclusions are
# applied first (rule funnels are written for both), then the weighted score ranks what is left, then the optimiser
# chooses a feasible set (lengths, spacing, totals), so selection never rests on the score alone.
#
# FIRE LINES. Candidate edge = 10 m outside the developed footprint (30 m building buffers of Open Buildings V3 + NCRP
# footprints, united with private land, closed by 40 m), cut into 100 m pieces. A piece is buildable only if it is on
# state land; has >= 10 WUI buildings within 200 m; lies 30-100 m from the nearest building (every sample point >= 30 m,
# median <= 100 m); fuel index >= 0.33; >= 60% of it crosses vegetation >= 50% cover; mean slope <= 30 deg; is clear of
# national/OSM motor roads (15 m), streams (15 m), major rivers (30 m) and drinking-water sources (10 m); and is outside
# JDWNP. Score = 0.30 exposure + 0.20 fuel + 0.20 topography + 0.15 fire history + 0.15 susceptibility.
#   (a) segmented: 500-1500 m segments, >= 300 m apart, exactly 5.0 km, both ends anchored on a road, footpath or stream
#       within 100 m; exact dynamic programming;
#   (b) continuous: one 5.0 km run of built line along one edge, unbuilt pass-through <= 25%, both ends anchored.
#   Width (criteria doc): 5 m where fuel index >= 0.67 or slope >= 20 deg; 5 m where fuel >= 0.33; else 6 m; 5 m cap > 25 deg.
# PRESCRIBED BURNS. Eligible 50 m cells: open shrub/grass (shrub+grass >= 20% and dominant over trees) or open blue pine
# (canopy < 30%, tree <= 40%); not fir/hemlock/spruce/broadleaf/alpine scrub; fuel index >= 0.40; 2000-3300 m; slope
# <= 25 deg; bare/sparse <= 20%; soil suitable for planting; cell edge >= 150 m from any building footprint; 100-750 m
# from a WUI building; <= 0.5 h walk from a road; not private land; >= 30 m from streams; >= 100 m from water sources.
# Burned-since-2023, JDWNP, RBP and biological corridors are flagged, not excluded. Compact 2-6 ha units grown from a
# 200 m seed lattice; 7 units, 24-26 ha, >= 500 m apart, chosen by integer programming (lpSolve).
# Run: Rscript thimphu_WUI/scripts/15_firelines_rxburn.R   (after 14)
source(if (file.exists("thimphu_WUI/R/tw_common.R")) "thimphu_WUI/R/tw_common.R" else "R/tw_common.R")
source(tw("R/sci_figure.R")); suppressPackageStartupMessages({ library(patchwork); library(lpSolve); library(lwgeom) })
terraOptions(memfrac = 0.5, progress = 0)
set.seed(20261126)
# ============================================================
# CONFIGURATION
# ============================================================
FM <- CFG$fire_management; FL <- FM$fire_lines; RX <- FM$rx_burn
SLUG <- FM$slug
TITLE <- "Fire-line siting and prescribed-burn site selection for the Thimphu wildland-urban interface"
IN <- tw(FM$inputs_dir); OUTD <- tw(FM$outputs_dir)
NP <- FL$total_m / FL$piece_m                          # pieces in 5 km
# ============================================================
run <- sci_run(SLUG, TITLE, inputs = c(file.path(IN, "x"), tw("data/inputs/x")))
dir.create(OUTD, recursive = TRUE, showWarnings = FALSE)
g <- grid50(); zone <- values(g, mat = FALSE); inth <- zone %in% 2
dz <- study_dz(); gw <- study_gewogs(); km2 <- (RES / 1000)^2
L <- st_layers(file.path(IN, "layers.gpkg"))$name
lay <- function(n) st_read(file.path(IN, "layers.gpkg"), n, quiet = TRUE)

# ---- rasters -------------------------------------------------------------------------------------------------
dem <- rast(file.path(IN, "dem_50m.tif")); slp <- rast(file.path(IN, "slope_deg_50m.tif")); asp <- rast(file.path(IN, "aspect_deg_50m.tif"))
fu <- rast(file.path(IN, "fuel_50m.tif")); prv <- rast(file.path(IN, "private_land_cover_50m.tif"))
vs <- rast(tw("data/inputs/vegetation_shares_50m.tif")); ft <- rast(tw("data/inputs/forest_type_50m.tif"))
sus <- rast(tw("data/inputs/susceptibility_class_50m.tif")); walk <- rast(tw("data/inputs/walk_time_h_50m.tif"))
cal <- rast(tw("data/derived/wui_class_calibrated_50m.tif"))
bare <- rast(file.path(IN, "bare_pct_50m.tif")); soil <- rast(file.path(IN, "soil_type_50m.tif"))
veg <- vs[["wc_tree"]] + vs[["wc_shrub"]] + vs[["wc_grass"]]; names(veg) <- "veg_pct"
ftl <- levels(ft)[[1]]; names(ftl) <- c("value", "forest_type")
flam_tab <- unlist(FM$forest_type_flammability)
flam <- classify(ft, cbind(ftl$value, unname(flam_tab[ftl$forest_type]))); names(flam) <- "flammability"
hs <- shade(terrain(dem, "slope", unit = "radians"), terrain(dem, "aspect", unit = "radians"), 40, 315)

# percentile transform of fuel descriptors against vegetated Thimphu cells
FUELV <- c("fuelbed_depth_cm", "litter_depth_cm", "shrub_cover_pct", "understorey_cover_pct")
vv <- values(veg, mat = FALSE) >= FL$min_veg_pct & inth
ecdfs <- lapply(FUELV, function(b) ecdf(values(fu[[b]], mat = FALSE)[vv & !is.na(values(fu[[b]], mat = FALSE))])); names(ecdfs) <- FUELV
fuel_pct <- function(df) rowMeans(sapply(FUELV, function(b) ecdfs[[b]](df[[b]])), na.rm = TRUE)

# ---- vectors ------------------------------------------------------------------------------------------------------
ob <- st_read(tw("data/derived/wui_thimphu.gpkg"), "buildings", quiet = TRUE)
nc <- lay("buildings_ncrp"); ncp <- suppressWarnings(st_centroid(nc))
ncp$class <- CLASSES[values(cal, mat = FALSE)[cellFromXY(g, st_coordinates(ncp))]]
ncp <- ncp[lengths(st_intersects(ncp, dz)) > 0, ]
ob$wui <- ob$class_calibrated %in% FM$wui_classes; ncp$wui <- ncp$class %in% FM$wui_classes
wob <- ob[ob$wui, ]; wnc <- ncp[ncp$wui, ]
roads <- st_read(tw("data/inputs/roads_osm.gpkg"), quiet = TRUE)
motor <- roads[roads$highway %in% FL$motor_roads, ]
streams <- lay("streams"); wsrc <- lay("water_sources"); pa <- lay("protected_areas"); pl <- lay("private_land")
vil <- rbind(st_sf(name = lay("major_villages")$name, geometry = st_geometry(lay("major_villages"))),
             st_sf(name = lay("village_points")$name, geometry = st_geometry(lay("village_points"))))
vil <- vil[!is.na(vil$name) & nzchar(trimws(vil$name)), ]
fe <- tw("data/inputs/fire_evidence.gpkg")
fdp <- st_read(fe, "dofps_points", quiet = TRUE); ffp <- st_read(fe, "firms_points", quiet = TRUE); fbp <- st_read(fe, "burned_patches", quiet = TRUE)
roads_nat <- lay("roads_national")
nogo <- lay("no_go_areas"); NGC <- FM$no_go_areas   # existing plantations and reserved / proposed sites: no fire lines, no burning
anchor_feat <- st_union(c(st_geometry(roads), st_geometry(roads_nat), st_geometry(streams)))
EX <- FL$exclusion   # hard no-build zone: roads and watercourses
ex_parts <- list(
  road = st_union(c(st_buffer(st_geometry(roads_nat), EX$road_m, nQuadSegs = 2), st_buffer(st_geometry(motor), EX$road_m, nQuadSegs = 2))),
  stream = st_union(st_buffer(st_geometry(streams[streams$kind == "stream", ]), EX$stream_m, nQuadSegs = 2)),
  river = st_union(st_buffer(st_geometry(streams[streams$kind == "river", ]), EX$river_m, nQuadSegs = 2)),
  water_source = st_union(st_buffer(st_geometry(wsrc), EX$water_source_m, nQuadSegs = 4)))
excl <- st_union(do.call(c, ex_parts))
bld_geom <- c(st_geometry(ob), st_geometry(nc))      # actual building geometry: Open Buildings points + NCRP footprint polygons
nearest_name <- function(x) { i <- st_nearest_feature(x, vil); list(name = vil$name[i], dist = as.numeric(st_distance(x, vil[i, ], by_element = TRUE))) }
unit_of <- function(x) { j <- st_intersects(x, gw); vapply(j, function(k) if (length(k)) gw$gewog[k[1]] else CFG$study_area$unassigned_unit, "") }
wgs <- function(x) round(st_coordinates(st_transform(x, 4326)), 6)

# =====================================================================================================================
# A. FIRE LINES
# =====================================================================================================================
message("A. developed footprint and candidate edge")
bpts <- c(st_geometry(ob), st_geometry(ncp))
CACHE <- file.path(OUTD, "cache_pieces.rds")
if (Sys.getenv("TW_FM_CACHE") == "1" && file.exists(CACHE)) { pieces <- readRDS(CACHE); message("  pieces read from cache") } else {
fp <- st_union(st_buffer(bpts, FL$footprint_building_buffer_m, nQuadSegs = 3))
fp <- st_union(fp, st_union(st_make_valid(st_geometry(pl))))
fp <- st_buffer(st_buffer(fp, FL$footprint_close_m, nQuadSegs = 3), -FL$footprint_close_m, nQuadSegs = 3)
fp_poly <- st_cast(st_sf(geometry = st_cast(fp, "MULTIPOLYGON")), "POLYGON", warn = FALSE)
drop_holes <- function(p, min_m2) { r <- p[1]; h <- p[-1]; if (length(h)) h <- h[vapply(h, function(z) abs(as.numeric(st_area(st_polygon(list(z))))) >= min_m2, TRUE)]; st_polygon(c(r, h)) }
fp_poly <- st_sfc(lapply(st_geometry(fp_poly), drop_holes, FL$min_hole_ha * 1e4), crs = CRS)
edge <- st_buffer(fp_poly, FL$line_offset_m, nQuadSegs = 3)
edge <- st_simplify(st_union(edge), dTolerance = 5)
rings <- st_cast(st_cast(st_boundary(edge), "MULTILINESTRING"), "LINESTRING")
rings <- rings[as.numeric(st_length(rings)) >= 3 * FL$piece_m]
rings <- rings[lengths(st_intersects(rings, dz)) > 0]
message(sprintf("  %d edge rings, %.0f km", length(rings), sum(as.numeric(st_length(rings))) / 1000))

pieces <- do.call(rbind, lapply(seq_along(rings), function(r) {
  len <- as.numeric(st_length(rings[r])); n <- max(1, round(len / FL$piece_m)); f <- (0:n) / n
  geo <- do.call(c, lapply(seq_len(n), function(i) st_linesubstring(rings[r], f[i], f[i + 1])))
  st_sf(ring = r, pos = seq_len(n), geometry = geo)
}))
pieces <- st_set_crs(pieces, CRS); pieces$len_m <- as.numeric(st_length(pieces))
pieces <- pieces[lengths(st_intersects(pieces, dz)) > 0, ]
pieces <- pieces[order(pieces$ring, pieces$pos), ]; pieces$pid <- seq_len(nrow(pieces))
message(sprintf("  %d pieces of ~%d m", nrow(pieces), FL$piece_m))

# sample 5 regular points per piece
sp <- st_cast(st_line_sample(st_geometry(pieces), n = 5, type = "regular"), "POINT")
spid <- rep(pieces$pid, each = 5)
sxy <- st_coordinates(sp); sc <- cellFromXY(g, sxy)
pv <- function(r) values(r, mat = FALSE)[sc]
S <- data.frame(pid = spid, veg = pv(veg), slope = pv(slp), aspect = pv(asp), elev = pv(dem), sus = pv(sus), flam = pv(flam), private = pv(prv))
for (b in FUELV) S[[b]] <- pv(fu[[b]])
S$fuel_pct <- fuel_pct(S)
S$road <- lengths(st_is_within_distance(sp, motor, FL$road_exclusion_m)) > 0
S$sw <- (1 + cos((S$aspect - 225) * pi / 180)) / 2
agg <- function(v, f = mean) as.numeric(tapply(v, S$pid, f, na.rm = TRUE)[as.character(pieces$pid)])
pieces$veg_share <- agg(S$veg >= FL$min_veg_pct); pieces$road_share <- agg(S$road)
pieces$slope_mean <- agg(S$slope); pieces$slope_max <- agg(S$slope, max); pieces$elev <- agg(S$elev)
pieces$sus_mean <- agg(S$sus); pieces$flam <- agg(S$flam); pieces$fuel_pct <- agg(S$fuel_pct); pieces$sw <- agg(S$sw)
for (b in FUELV) pieces[[b]] <- agg(S[[b]])
pieces$private_share <- agg(S$private)
# exposure: WUI buildings within 200 m (larger of the two building sources)
nob <- lengths(st_is_within_distance(pieces, wob, FL$exposure_radius_m)); nnc <- lengths(st_is_within_distance(pieces, wnc, FL$exposure_radius_m))
pieces$wui_bld_ob <- nob; pieces$wui_bld_ncrp <- nnc; pieces$wui_bld <- pmax(nob, nnc)
# houses upslope: median elevation of WUI buildings within 200 m minus piece elevation
wob$elev <- values(dem, mat = FALSE)[cellFromXY(g, st_coordinates(wob))]
near <- st_is_within_distance(pieces, wob, FL$exposure_radius_m)
pieces$bld_elev <- vapply(near, function(k) if (length(k)) median(wob$elev[k], na.rm = TRUE) else NA_real_, 0)
pieces$downslope_m <- pieces$bld_elev - pieces$elev
# fire evidence within 1 km
pieces$fire_n <- lengths(st_is_within_distance(pieces, fdp, FL$fire_radius_m)) + lengths(st_is_within_distance(pieces, ffp, FL$fire_radius_m)) +
  lengths(st_is_within_distance(pieces, fbp, FL$fire_radius_m))
# anchors at the piece ends
ends <- st_line_sample(st_geometry(pieces), sample = c(0, 1)); ends <- st_cast(ends, "POINT")
anc <- lengths(st_is_within_distance(ends, anchor_feat, FL$anchor_m)) > 0
pieces$anchor_start <- anc[seq(1, length(anc), 2)]; pieces$anchor_end <- anc[seq(2, length(anc), 2)]
pieces$in_pa <- lengths(st_intersects(pieces, pa)) > 0
saveRDS(pieces, CACHE) }

# ---- attributes added for the refined criteria (outside the cache) ---------------------------------------------------
spx <- st_cast(st_line_sample(st_geometry(pieces), n = 5, type = "regular"), "POINT"); spx_id <- rep(pieces$pid, each = 5)
stopifnot(length(spx) == 5 * nrow(pieces))
agg5 <- function(v, f) as.numeric(tapply(v, spx_id, f, na.rm = TRUE)[as.character(pieces$pid)])
d_pt <- as.numeric(st_distance(spx, bld_geom[st_nearest_feature(spx, bld_geom)], by_element = TRUE))
pieces$bld_dist_min <- agg5(d_pt, min); pieces$bld_dist_med <- agg5(d_pt, median)
pieces$walk_h <- agg5(values(walk, mat = FALSE)[cellFromXY(g, st_coordinates(spx))], mean)
pieces$on_road_river <- lengths(st_intersects(pieces, excl)) > 0
ex_hit <- sapply(ex_parts, function(z) lengths(st_intersects(pieces, z)) > 0)
pieces$on_road <- ex_hit[, "road"]; pieces$on_stream_river <- ex_hit[, "stream"] | ex_hit[, "river"]; pieces$on_water_source <- ex_hit[, "water_source"]
pieces$on_private <- lengths(st_intersects(pieces, st_make_valid(pl))) > 0
pieces$in_jdwnp <- lengths(st_intersects(pieces, pa[pa$park %in% FL$excluded_pa, ])) > 0
pa_name <- function(x) vapply(st_intersects(x, pa), function(k) if (length(k)) paste(unique(pa$PA_name[k]), collapse = "+") else "", "")
pieces$in_nogo <- lengths(st_is_within_distance(pieces, nogo, max(NGC$fire_line_buffer_m, 0.01))) > 0
pieces$c_fuel <- 0.7 * pieces$fuel_pct + 0.3 * pieces$flam
# mandatory exclusions, in the order of the criteria document (cumulative funnel)
FRULES <- list(
  `Candidate edge outside the developed footprint` = rep(TRUE, nrow(pieces)),
  `State land only (no private land)` = !pieces$on_private,
  `>= 10 WUI buildings within 200 m` = pieces$wui_bld >= FL$min_wui_buildings,
  `30-100 m from nearest building` = pieces$bld_dist_min >= FL$building_distance_m[1] & pieces$bld_dist_med <= FL$building_distance_m[2],
  `Fuel index >= 0.33` = pieces$c_fuel >= FL$min_fuel_index,
  `>= 60% through vegetation >= 50% cover` = pieces$veg_share >= FL$min_veg_point_share,
  `Slope <= 30 deg` = pieces$slope_mean <= FL$max_slope_deg,
  `>= 15 m from roads (national, OSM motor/track)` = !pieces$on_road,
  `>= 15 m from streams, >= 30 m from rivers` = !pieces$on_stream_river,
  `>= 10 m from drinking-water sources` = !pieces$on_water_source,
  `Outside JDWNP` = !pieces$in_jdwnp,
  `Outside existing plantations and reserved sites` = !pieces$in_nogo)
FRULES <- lapply(FRULES, function(x) !is.na(x) & x)
pieces$feasible <- Reduce(`&`, FRULES)
funnel_fl <- data.frame(rule = names(FRULES), pieces_passing_rule = vapply(FRULES, sum, 0),
                        km_passing_rule = vapply(FRULES, function(x) round(sum(pieces$len_m[x]) / 1000, 1), 0),
                        cumulative_pieces = vapply(seq_along(FRULES), function(i) sum(Reduce(`&`, FRULES[seq_len(i)])), 0),
                        cumulative_km = vapply(seq_along(FRULES), function(i) round(sum(pieces$len_m[Reduce(`&`, FRULES[seq_len(i)])]) / 1000, 1), 0))
print(funnel_fl)
pieces$steep <- pieces$slope_mean > FL$max_slope_deg
pr01 <- function(x, ref = x) { e <- ecdf(ref[is.finite(ref)]); y <- e(x); y[!is.finite(x)] <- 0; y }
fz <- pieces$feasible
pieces$c_exposure <- pr01(log1p(pieces$wui_bld), log1p(pieces$wui_bld[fz]))
pieces$c_fire <- pr01(log1p(pieces$fire_n), log1p(pieces$fire_n[fz]))
pieces$c_susceptibility <- (pieces$sus_mean - 1) / 4
pieces$c_topography <- 0.6 * pmin(1, pmax(0, ifelse(is.na(pieces$downslope_m), 0, pieces$downslope_m) / 50)) + 0.4 * pieces$sw
COMP <- c("exposure", "fuel", "fire", "susceptibility", "topography")
for (k in COMP) pieces[[paste0("c_", k)]][!is.finite(pieces[[paste0("c_", k)]])] <- 0
score_with <- function(w) { w <- unlist(w)[COMP]; w <- w / sum(w); as.numeric(as.matrix(st_drop_geometry(pieces)[paste0("c_", COMP)]) %*% w) }
pieces$score <- score_with(FL$weights)
W <- FL$width
pieces$width_m <- ifelse(pieces$c_fuel >= W$high_fuel_index | pieces$slope_mean >= W$steep_deg, W$high_m, ifelse(pieces$c_fuel >= W$medium_fuel_index, W$medium_m, W$other_m))
pieces$width_m <- ifelse(pieces$slope_mean > W$cap_slope_deg, pmin(pieces$width_m, W$cap_m), pieces$width_m)
pieces$rank_feasible <- NA_integer_; pieces$rank_feasible[fz] <- rank(-pieces$score[fz], ties.method = "first")
message(sprintf("  feasible pieces: %d of %d (%.0f km)", sum(fz), nrow(pieces), sum(pieces$len_m[fz]) / 1000))

# ---- runs of buildable pieces along each ring (rotated so a closed ring starts at a break) ----------------------------
order_ring <- function(d, brk) {               # d: piece rows of one ring in order; brk: logical break flag
  if (any(brk) && !brk[1]) { s <- which(brk)[1]; d <- d[c(s:nrow(d), seq_len(s - 1)), ] }
  d
}
P <- st_drop_geometry(pieces)
seg_runs <- do.call(rbind, lapply(split(P, P$ring), function(d) {
  d <- order_ring(d, !d$feasible); r <- cumsum(c(1, diff(d$feasible) != 0)); d$run <- paste(d$ring, r, sep = "_"); d[d$feasible, ]
}))

# exact DP: intervals of Lmin..Lmax pieces, >= G pieces apart, total exactly B pieces
dp_segments <- function(runs_df, v, B, Lmin, Lmax, G, lambda, beta, need_anchor = FALSE) {
  runs <- split(seq_len(nrow(runs_df)), runs_df$run); runs <- runs[lengths(runs) >= Lmin]
  NEG <- -1e18; best <- list()
  for (nm in names(runs)) {
    ix <- runs[[nm]]; n <- length(ix); val <- v[ix]; cs <- c(0, cumsum(val))
    as <- runs_df$anchor_start[ix]; ae <- runs_df$anchor_end[ix]
    F <- matrix(NEG, n + 1, B + 1); F[1, 1] <- 0; CH <- matrix(0L, n + 1, B + 1)
    base <- c(0, rep(NEG, B))
    for (j in seq_len(n)) {
      F[j + 1, ] <- F[j, ]
      if (j >= Lmin) for (Ln in Lmin:min(Lmax, j)) {
        a <- j - Ln + 1; if (need_anchor && !(as[a] && ae[j])) next
        s <- cs[j + 1] - cs[a] + beta * (as[a] + ae[j]) - lambda
        p <- j - Ln - G; prev <- if (p >= 0) F[p + 1, ] else if (j - Ln == 0 || p < 0) base else base
        cand <- c(rep(NEG, Ln), prev[seq_len(B + 1 - Ln)] + s)
        if (length(cand) != B + 1) stop(sprintf("DP length %d (Ln %d, j %d, len s %d, len prev %d)", length(cand), Ln, j, length(s), length(prev)))
        up <- cand > F[j + 1, ]; F[j + 1, up] <- cand[up]; CH[j + 1, up] <- Ln
      }
    }
    best[[nm]] <- list(ix = ix, F = F, CH = CH, g = F[n + 1, ])
  }
  # knapsack over runs
  R <- length(best); H <- matrix(NEG, R + 1, B + 1); H[1, 1] <- 0; K <- matrix(0L, R + 1, B + 1)
  for (r in seq_len(R)) { gr <- best[[r]]$g
    for (b in 0:B) { k <- 0:b; c2 <- H[r, b - k + 1] + gr[k + 1]; m <- which.max(c2); H[r + 1, b + 1] <- c2[m]; K[r + 1, b + 1] <- k[m] } }
  if (H[R + 1, B + 1] < -1e17) return(NULL)
  sel <- list(); b <- B
  for (r in R:1) { k <- K[r + 1, b + 1]; b <- b - k
    if (k > 0) { bb <- best[[r]]; j <- length(bb$ix); kk <- k
      while (kk > 0 && j > 0) { Ln <- bb$CH[j + 1, kk + 1]
        if (Ln == 0) { j <- j - 1 } else { sel[[length(sel) + 1]] <- bb$ix[(j - Ln + 1):j]; kk <- kk - Ln; j <- j - Ln - G } } } }
  sel
}
S1 <- FL$segmented; Lmin <- S1$min_m / FL$piece_m; Lmax <- S1$max_m / FL$piece_m; G <- S1$min_gap_m / FL$piece_m
run_segmented <- function(score) {
  v <- score[match(seg_runs$pid, pieces$pid)]
  sel <- dp_segments(seg_runs, v, NP, Lmin, Lmax, G, S1$segment_penalty, S1$anchor_bonus, isTRUE(FL$require_anchor_both_ends))
  lapply(sel, function(ix) seg_runs$pid[ix])
}
message("A1. segmented option (dynamic programming)")
segA <- run_segmented(pieces$score)

# continuous: one window along a ring, built length = 5 km, pass-through <= 25%, no steep pieces
run_continuous <- function(score) {
  best <- NULL; bv <- -Inf
  for (d in split(P, P$ring)) {
    d <- order_ring(d, d$steep); d$score <- score[match(d$pid, pieces$pid)]
    r <- cumsum(c(1, diff(d$steep) != 0))
    for (rr in unique(r[!d$steep])) {
      x <- d[r == rr, ]; if (sum(x$feasible) < NP) next
      cb <- c(0, cumsum(x$feasible)); cv <- c(0, cumsum(ifelse(x$feasible, x$score, 0)))
      for (s in seq_len(nrow(x))) {
        e <- which(cb >= cb[s] + NP)[1] - 1; if (is.na(e)) break
        if (!x$feasible[s] || !x$feasible[e]) next
        if (isTRUE(FL$require_anchor_both_ends) && !(x$anchor_start[s] && x$anchor_end[e])) next
        span <- e - s + 1; if ((span - NP) > FL$max_pass_through_share * NP) next
        val <- cv[e + 1] - cv[s] + FL$continuous$anchor_bonus * (x$anchor_start[s] + x$anchor_end[e])
        if (val > bv) { bv <- val; best <- x$pid[s:e] }
      }
    }
  }
  best
}
message("A2. continuous option")
conA <- run_continuous(pieces$score)
CONT_OK <- !is.null(conA)
# longest continuous run that meets every rule (built pieces, pass-through <= 25%, anchored both ends, no steep break)
longest_run <- function() { best <- 0
  for (d in split(P, P$ring)) { n <- nrow(d); if (!any(d$feasible)) next
    for (s0 in which(d$feasible & d$anchor_start)) { b <- 0; for (e in s0:n) { if (d$steep[e]) break; b <- b + d$feasible[e]
      if (d$feasible[e] && d$anchor_end[e] && (e - s0 + 1 - b) <= FL$max_pass_through_share * b && b > best) best <- b } } }
  best * FL$piece_m }
CONT_MAX_M <- longest_run()
message(sprintf("  continuous 5 km option feasible: %s (longest compliant continuous run %d m)", CONT_OK, CONT_MAX_M))

# ---- build segment features and tables ---------------------------------------------------------------------------------
make_lines <- function(sel_list, option) {
  do.call(rbind, lapply(seq_along(sel_list), function(i) {
    ids <- sel_list[[i]]; pp <- pieces[match(ids, pieces$pid), ]; built <- pp[pp$feasible, ]
    geo <- st_line_merge(st_cast(st_union(st_geometry(built)), "MULTILINESTRING"))   # built parts only; road/river crossings and fields stay unbuilt
    mid <- st_line_sample(st_geometry(pp)[ceiling(nrow(pp) / 2)], sample = 0.5) |> st_cast("POINT")
    endsx <- st_cast(st_line_sample(st_geometry(pp)[c(1, nrow(pp))], sample = c(0, 1)), "POINT")[c(1, 4)]
    nn <- nearest_name(mid[1]); bl <- st_is_within_distance(st_union(st_geometry(built)), wob, FL$exposure_radius_m)[[1]]
    bn <- st_is_within_distance(st_union(st_geometry(built)), wnc, FL$exposure_radius_m)[[1]]
    ll <- wgs(endsx)
    st_sf(option = option, segment = sprintf("%s-%02d", substr(option, 1, 1) |> toupper(), i), gewog = unit_of(mid[1]), nearest_village = nn$name,
          village_dist_m = round(nn$dist), built_length_m = round(sum(built$len_m)), pass_through_m = round(sum(pp$len_m[!pp$feasible])),
          width_m_mix = { ww <- sort(unique(built$width_m)); paste(sprintf("%dm:%d%%", ww, round(100 * vapply(ww, function(w) sum(built$len_m[built$width_m == w]), 0) / sum(built$len_m))), collapse = " ") },
          cleared_ha = round(sum(built$len_m * built$width_m) / 1e4, 2), slope_mean_deg = round(weighted.mean(built$slope_mean, built$len_m), 1),
          slope_max_deg = round(max(built$slope_max, na.rm = TRUE), 1), elev_min_m = round(min(built$elev, na.rm = TRUE)), elev_max_m = round(max(built$elev, na.rm = TRUE)),
          wui_buildings_200m = max(length(bl), length(bn)), wui_buildings_ob = length(bl), wui_buildings_ncrp = length(bn),
          fuel_index = round(mean(built$c_fuel), 2), fuelbed_depth_cm = round(mean(built$fuelbed_depth_cm, na.rm = TRUE), 1),
          shrub_cover_pct = round(mean(built$shrub_cover_pct, na.rm = TRUE)), fire_evidence_1km = max(built$fire_n),
          houses_upslope_share = round(mean(built$downslope_m > 0, na.rm = TRUE), 2), score_mean = round(mean(built$score), 3),
          comp_exposure = round(mean(built$c_exposure), 3), comp_fuel = round(mean(built$c_fuel), 3), comp_fire = round(mean(built$c_fire), 3),
          comp_susceptibility = round(mean(built$c_susceptibility), 3), comp_topography = round(mean(built$c_topography), 3),
          nearest_building_m = round(min(built$bld_dist_min)), building_dist_median_m = round(median(built$bld_dist_med)), walk_h_mean = round(mean(built$walk_h, na.rm = TRUE), 2),
          anchored_start = pp$anchor_start[1], anchored_end = pp$anchor_end[nrow(pp)], in_protected_area = any(pp$in_pa),
          protected_area_flag = { z <- pa_name(st_union(st_geometry(built))); if (nzchar(z)) z else "none" },
          start_lon = ll[1, 1], start_lat = ll[1, 2], end_lon = ll[2, 1], end_lat = ll[2, 2], geometry = geo)
  }))
}
LS <- make_lines(segA, "segmented"); LS <- LS[order(-LS$score_mean), ]; LS$segment <- sprintf("S-%02d", seq_len(nrow(LS)))
LC <- if (CONT_OK) { x <- make_lines(list(conA), "continuous"); x$segment <- "C-01"; x } else NULL
message(sprintf("  segmented: %d segments, %d m; continuous: %s", nrow(LS), sum(LS$built_length_m), if (CONT_OK) sprintf("%d m built", LC$built_length_m) else "none feasible"))

# =====================================================================================================================
# B. PRESCRIBED-BURN SITES
# =====================================================================================================================
message("B. prescribed-burn eligibility")
cv <- function(r) values(r, mat = FALSE)
allb <- rasterize(vect(st_sf(geometry = bpts)), g, fun = "count"); d_bld <- distance(allb)
wcount <- max(rasterize(vect(wob), g, fun = "count", background = 0), rasterize(vect(wnc), g, fun = "count", background = 0))
d_wui <- distance(classify(wcount, cbind(0, NA)))
expo1k <- focal(wcount, circle_w(g, RX$exposure_radius_m), fun = "sum", na.rm = TRUE)
evc <- rasterize(vect(rbind(st_sf(geometry = st_geometry(fdp)), st_sf(geometry = st_geometry(ffp)))), g, fun = "count", background = 0) +
  rasterize(vect(fbp), g, field = 1, background = 0, touches = TRUE)
fire1k <- focal(evc, circle_w(g, 1000), fun = "sum", na.rm = TRUE)
recent <- rasterize(vect(fbp[as.integer(substr(fbp$fire_date, 1, 4)) >= RX$recent_burn_from_year, ]), g, field = 1, background = 0, touches = TRUE)
nogo_r <- rasterize(vect(st_buffer(nogo, NGC$rx_buffer_m)), g, field = 1, background = 0, touches = TRUE)
pa_flag <- rasterize(vect(pa[pa$park %in% RX$flag_pa, ]), g, field = 1, background = 0, touches = TRUE)
d_str <- distance(rasterize(vect(streams), g, field = 1, touches = TRUE))
d_ws <- distance(rasterize(vect(wsrc), g, field = 1))
gid <- rast(tw("data/inputs/gewog_50m.tif")); glev <- levels(gid)[[1]]
roads_hold <- rasterize(vect(roads), g, field = 1, touches = TRUE)
fl_r <- rasterize(vect(LS), g, field = 1, touches = TRUE)
d_hold <- distance(cover(cover(roads_hold, rasterize(vect(streams), g, field = 1, touches = TRUE)), fl_r))
soil_lev <- levels(soil)[[1]]; names(soil_lev) <- c("value", "soil")

C <- data.frame(cell = seq_len(ncell(g)), inth = inth, veg = cv(veg), shrub = cv(vs[["wc_shrub"]]), grass = cv(vs[["wc_grass"]]), tree = cv(vs[["wc_tree"]]),
                crop = cv(vs[["wc_crop"]]), built = cv(vs[["wc_built"]]), ft = ftl$forest_type[match(cv(ft), ftl$value)], canopy = cv(fu[["canopy_cover_pct"]]),
                elev = cv(dem), slope = cv(slp), aspect = cv(asp), d_bld = cv(d_bld), d_wui = cv(d_wui), walk = cv(walk), private = cv(prv),
                pa = cv(pa_flag), d_str = cv(d_str), d_ws = cv(d_ws), recent = cv(recent), sus = cv(sus), expo = cv(expo1k), fire = cv(fire1k),
                d_hold = cv(d_hold), flam = cv(flam), nogo = cv(nogo_r), bare = cv(bare), soil = soil_lev$soil[match(cv(soil), soil_lev$value)])
for (b in c(FUELV, "canopy_cover_pct", "cwd_biomass_mg_ha", "litter_cover_pct")) C[[b]] <- cv(fu[[b]])
C$gewog <- glev[[2]][match(cv(gid), glev[[1]])]; C$gewog[is.na(C$gewog)] <- CFG$study_area$unassigned_unit
C$fuel_index <- 0.7 * fuel_pct(C) + 0.3 * C$flam
# open shrubland/grassland: shrub+grass >= 20% and shrub+grass the dominant cover (not tree-dominated)
C$open <- (C$shrub + C$grass) >= RX$min_open_veg_pct & (C$shrub + C$grass) >= C$tree
C$bp_open <- C$ft %in% RX$burnable_forest_types & C$canopy < RX$max_canopy_pct_forest & C$tree <= RX$max_tree_pct_open_pine & C$veg >= RX$min_open_veg_pct
C$fuel_ok <- (C$open | C$bp_open) & (C$crop + C$built) < 20
C$soil_ok <- is.na(C$soil) | !grepl(paste(RX$unsuitable_soil_patterns, collapse = "|"), C$soil, ignore.case = TRUE)
rules <- list(
  `Thimphu dzongkhag` = C$inth,
  `Open shrub/grass (>= 20%) or open blue pine (canopy < 30%, tree <= 40%)` = C$fuel_ok,
  `Not fir, hemlock, spruce, broadleaf or alpine scrub` = !(C$ft %in% RX$excluded_forest_types),
  `Fuel index >= 0.40` = C$fuel_index >= RX$min_fuel_index,
  `Elevation 2000-3300 m` = C$elev >= RX$elev_m[1] & C$elev <= RX$elev_m[2],
  `Slope <= 25 deg` = C$slope <= RX$max_slope_deg,
  `Bare/sparse ground <= 20%` = C$bare <= RX$max_bare_pct,
  `Soil suitable for planting` = C$soil_ok,
  `>= 150 m from any building` = C$d_bld >= RX$min_building_m + RES / sqrt(2),   # cell edge, not centre
  `0.1-0.75 km from a WUI building` = C$d_wui >= RX$wui_building_m[1] & C$d_wui <= RX$wui_building_m[2],
  `<= 0.5 h walk from a road` = C$walk <= RX$max_walk_h,
  `Not private land` = C$private < 0.1,
  `>= 30 m from streams` = C$d_str >= RX$stream_buffer_m,
  `>= 100 m from water sources` = C$d_ws >= RX$water_source_buffer_m,
  `>= 50 m from existing plantations and reserved sites` = C$nogo == 0)
rules <- lapply(rules, function(x) !is.na(x) & x)
elig <- Reduce(`&`, rules); C$elig <- elig
funnel <- data.frame(rule = names(rules), cells_passing_rule = vapply(rules, function(x) sum(x & C$inth), 0),
                     cumulative_cells = vapply(seq_along(rules), function(i) sum(Reduce(`&`, rules[seq_len(i)])), 0))
funnel$cumulative_ha <- funnel$cumulative_cells * km2 * 100
message(sprintf("  eligible: %.0f ha", sum(elig) * km2 * 100))
# exact check on the 50 m square against actual building geometry (Open Buildings points, NCRP footprint polygons)
sq <- st_as_sfc(lapply(which(elig), function(i) { x <- xFromCell(g, i); y <- yFromCell(g, i); h <- RES / 2
  st_polygon(list(rbind(c(x - h, y - h), c(x + h, y - h), c(x + h, y + h), c(x - h, y + h), c(x - h, y - h)))) }), crs = CRS)
nb_i <- st_nearest_feature(sq, bld_geom)
d_exact <- as.numeric(st_distance(sq, bld_geom[nb_i], by_element = TRUE))
drop_c <- which(elig)[d_exact < RX$min_building_m]; elig[drop_c] <- FALSE; C$elig <- elig
funnel <- rbind(funnel, data.frame(rule = ">= 150 m from any building (exact cell-edge check on footprints)", cells_passing_rule = NA, cumulative_cells = sum(elig),
                                   cumulative_ha = sum(elig) * km2 * 100))
print(funnel)
E <- C[elig, ]
rx_comp <- function(E) data.frame(
  fuel = E$fuel_index,
  exposure = pr01(log1p(E$expo)),
  susceptibility = (E$sus - 1) / 4,
  fire = pr01(log1p(E$fire)),
  access = pmax(0, 1 - E$walk / RX$max_walk_h))
RC <- rx_comp(E); RC[!is.finite(as.matrix(RC))] <- 0
rx_score_with <- function(w) { w <- unlist(w)[names(RC)]; w <- w / sum(w); as.numeric(as.matrix(RC) %*% w) }
E$score <- rx_score_with(RX$weights)
SUIT <- data.frame(cell = E$cell, score = E$score, fuel_index = E$fuel_index)   # all eligible cells, before the patch-size filter
E$hold <- E$d_hold <= RX$holding_m

# ---- grow compact candidate units ---------------------------------------------------------------------------------------
message("B1. candidate burn units")
NC <- ncol(g); NR <- nrow(g); rc_row <- function(i) (i - 1) %/% NC + 1; rc_col <- function(i) (i - 1) %% NC + 1
eligset <- rep(FALSE, ncell(g)); eligset[E$cell] <- TRUE
pt <- patches(setValues(rast(g), ifelse(eligset, 1, NA)), directions = 8); E$patch <- cv(pt)[E$cell]
psize <- table(E$patch); keep <- E$patch %in% as.integer(names(psize)[psize >= min(RX$site_ha) * 4]); E <- E[keep, ]; RC <- RC[keep, ]
erow <- rc_row(E$cell); ecol <- rc_col(E$cell); step <- RX$seed_spacing_m / RES
seeds <- E$cell[erow %% step == 0 & ecol %% step == 0]
seeds <- unique(c(seeds, vapply(split(seq_len(nrow(E)), E$patch), function(k) E$cell[k[which.max(E$score[k])]], 0)))
sizes <- RX$site_ha * 4; smax <- max(sizes)
grow <- function(seed) {
  sr <- rc_row(seed); sc0 <- rc_col(seed); unit <- seed; front <- integer()
  inU <- function(x) x %in% unit
  add_nb <- function(i) { r <- rc_row(i); c <- rc_col(i); nb <- c(if (c > 1) i - 1, if (c < NC) i + 1, if (r > 1) i - NC, if (r < NR) i + NC); nb[eligset[nb]] }
  front <- setdiff(add_nb(seed), unit); out <- list()
  while (length(unit) < smax && length(front)) {
    d2 <- (rc_row(front) - sr)^2 + (rc_col(front) - sc0)^2; k <- front[which.min(d2)]
    unit <- c(unit, k); front <- setdiff(unique(c(front, add_nb(k))), unit)
    if (length(unit) %in% sizes) out[[as.character(length(unit))]] <- unit
  }
  out
}
cand <- list(); for (s in seeds) { u <- grow(s); for (nm in names(u)) cand[[length(cand) + 1]] <- list(seed = s, cells = u[[nm]]) }
E_idx <- match(seq_len(ncell(g)), E$cell)
boundary_share <- function(cells) {
  r <- rc_row(cells); c <- rc_col(cells); nbs <- cbind(cells - 1, cells + 1, cells - NC, cells + NC)
  edgec <- apply(nbs, 1, function(z) any(!z %in% cells)); mean(E$hold[E_idx[cells[edgec]]])
}
CU <- do.call(rbind, lapply(seq_along(cand), function(i) { cc <- cand[[i]]$cells; k <- E_idx[cc]
  data.frame(cid = i, seed = cand[[i]]$seed, n = length(cc), ha = length(cc) * km2 * 100, score_cells = mean(E$score[k]), hold = boundary_share(cc),
             x = mean(xFromCell(g, cc)), y = mean(yFromCell(g, cc)), gewog = names(sort(table(E$gewog[k]), decreasing = TRUE))[1]) }))
unit_score <- function(cs, hold) (1 - RX$holding_weight) * cs + RX$holding_weight * hold
CU$score <- unit_score(CU$score_cells, CU$hold)
CU$fuel_index <- vapply(CU$cid, function(i) mean(E$fuel_index[E_idx[cand[[i]]$cells]]), 0)
CU$rank <- rank(-CU$score, ties.method = "first")
message(sprintf("  %d candidate units from %d seeds", nrow(CU), length(seeds)))

select_units <- function(CU, cell_score = NULL) {
  if (!is.null(cell_score)) CU$score <- unit_score(vapply(CU$cid, function(i) mean(cell_score[E_idx[cand[[i]]$cells]]), 0), CU$hold)
  bs <- tapply(CU$score, CU$seed, max); top <- as.numeric(names(sort(bs, decreasing = TRUE)))[seq_len(min(length(bs), RX$candidate_pool / length(sizes)))]
  Q <- CU[CU$seed %in% top, ]; n <- nrow(Q)
  dd <- as.matrix(dist(Q[, c("x", "y")])); conf <- which(upper.tri(dd) & (dd < RX$min_separation_m | outer(Q$seed, Q$seed, "==")), arr.ind = TRUE)
  A <- rbind(rep(1, n), Q$ha, Q$ha); dir <- c("=", ">=", "<="); rhs <- c(RX$n_sites, RX$target_total_ha - RX$total_tolerance_ha, RX$target_total_ha + RX$total_tolerance_ha)
  if (length(RX$max_per_gewog)) for (gg in unique(Q$gewog)) { A <- rbind(A, as.numeric(Q$gewog == gg)); dir <- c(dir, "<="); rhs <- c(rhs, RX$max_per_gewog) }
  if (nrow(conf)) { M <- matrix(0, nrow(conf), n); M[cbind(seq_len(nrow(conf)), conf[, 1])] <- 1; M[cbind(seq_len(nrow(conf)), conf[, 2])] <- 1
    A <- rbind(A, M); dir <- c(dir, rep("<=", nrow(conf))); rhs <- c(rhs, rep(1, nrow(conf))) }
  sol <- lp("max", Q$score * Q$ha, A, dir, rhs, all.bin = TRUE)
  if (sol$status != 0) return(NULL)
  Q[sol$solution > 0.5, ]
}
message("B2. integer programme")
SEL <- select_units(CU); stopifnot(!is.null(SEL)); SEL <- SEL[order(-SEL$score), ]

cells_poly <- function(cells) { r <- rast(g); v <- rep(NA, ncell(g)); v[cells] <- 1; values(r) <- v
  p <- st_as_sf(as.polygons(trim(r), dissolve = TRUE)); st_set_crs(st_union(st_geometry(p)), CRS) }
RXS <- do.call(rbind, lapply(seq_len(nrow(SEL)), function(i) {
  cc <- cand[[SEL$cid[i]]]$cells; k <- E_idx[cc]; e <- E[k, ]; geo <- cells_poly(cc); cen <- st_centroid(geo); nn <- nearest_name(cen); ll <- wgs(cen)
  bd <- min(as.numeric(st_distance(geo, bld_geom))); w500 <- max(lengths(st_is_within_distance(geo, wob, 500)), lengths(st_is_within_distance(geo, wnc, 500)))
  w1k <- max(lengths(st_is_within_distance(geo, wob, 1000)), lengths(st_is_within_distance(geo, wnc, 1000)))
  db <- as.numeric(st_distance(geo, fbp)); j <- which.min(db)
  asp_m <- (atan2(mean(sin(e$aspect * pi / 180)), mean(cos(e$aspect * pi / 180))) * 180 / pi) %% 360
  st_sf(site = sprintf("RX-%02d", i), gewog = SEL$gewog[i], nearest_village = nn$name, village_dist_m = round(nn$dist), area_ha = SEL$ha[i],
        centroid_lon = ll[1], centroid_lat = ll[2], elev_mean_m = round(mean(e$elev)), elev_min_m = round(min(e$elev)), elev_max_m = round(max(e$elev)),
        slope_mean_deg = round(mean(e$slope), 1), slope_max_deg = round(max(e$slope), 1),
        aspect = c("N", "NE", "E", "SE", "S", "SW", "W", "NW")[floor(((asp_m + 22.5) %% 360) / 45) + 1],
        forest_type = names(sort(table(e$ft), decreasing = TRUE))[1], open_shrub_grass_cells_pct = round(100 * mean(e$open)),
        tree_pct = round(mean(e$tree)), shrub_pct = round(mean(e$shrub)), grass_pct = round(mean(e$grass)), canopy_cover_pct = round(mean(e$canopy_cover_pct, na.rm = TRUE)),
        fuelbed_depth_cm = round(mean(e$fuelbed_depth_cm, na.rm = TRUE), 1), litter_depth_cm = round(mean(e$litter_depth_cm, na.rm = TRUE), 1), shrub_cover_nfi_pct = round(mean(e$shrub_cover_pct, na.rm = TRUE)),
        understorey_cover_pct = round(mean(e$understorey_cover_pct, na.rm = TRUE)), cwd_biomass_mg_ha = round(mean(e$cwd_biomass_mg_ha, na.rm = TRUE), 1),
        nearest_building_m = round(bd), wui_buildings_500m = w500, wui_buildings_1km = w1k, walk_h_mean = round(mean(e$walk), 2),
        holding_edge_share = round(SEL$hold[i], 2), score = round(SEL$score[i], 3),
        comp_fuel = round(mean(RC$fuel[k]), 3), comp_exposure = round(mean(RC$exposure[k]), 3), comp_susceptibility = round(mean(RC$susceptibility[k]), 3),
        comp_fire = round(mean(RC$fire[k]), 3), comp_access = round(mean(RC$access[k]), 3),
        nearest_burn_patch = fbp$event_id[j], nearest_burn_date = fbp$fire_date[j], nearest_burn_m = round(db[j]),
        fuel_index = round(mean(e$fuel_index), 2), bare_pct = round(mean(e$bare), 1), soil_type = names(sort(table(e$soil), decreasing = TRUE))[1],
        wui_building_dist_m = round(min(e$d_wui)), burned_since_2023_pct = round(100 * mean(e$recent > 0)),
        protected_area_flag = { z <- pa_name(geo); if (nzchar(z)) z else "none" },
        in_biological_corridor = any(lengths(st_intersects(geo, pa[grepl("Corridor", pa$park), ])) > 0),
        holding_ge_50pct = SEL$hold[i] >= 0.5, candidate_rank = SEL$rank[i], geometry = geo)
}))
message(sprintf("  %d sites, %.2f ha", nrow(RXS), sum(RXS$area_ha)))

# =====================================================================================================================
# C. SENSITIVITY TO WEIGHTS
# =====================================================================================================================
message("C. weight sensitivity")
alt <- function(base, nm) { w <- unlist(base); out <- list(`Equal weights` = setNames(rep(1, length(w)), names(w)))
  for (k in names(w)) { v <- w; v[k] <- v[k] * 2; out[[sprintf("Double %s", k)]] <- v }
  for (k in names(w)) { v <- w; v[k] <- 0; out[[sprintf("Drop %s", k)]] <- v }
  out }
jac <- function(a, b) length(intersect(a, b)) / length(union(a, b))
base_seg <- unlist(segA); base_con <- conA
SENS_FL <- do.call(rbind, lapply(names(alt(FL$weights)), function(nm) { w <- alt(FL$weights)[[nm]]; s <- score_with(w)
  a <- unlist(run_segmented(s)); b <- run_continuous(s)
  near_alt <- st_is_within_distance(LS, st_union(st_geometry(pieces)[match(a, pieces$pid)]), 300)
  data.frame(scenario = nm, segmented_jaccard = jac(a, base_seg), segments_retained_300m = mean(lengths(near_alt) > 0),
             continuous_jaccard = if (is.null(b)) NA else jac(b, base_con)) }))
base_cells <- unlist(lapply(SEL$cid, function(i) cand[[i]]$cells))
SENS_RX <- do.call(rbind, lapply(names(alt(RX$weights)), function(nm) { w <- alt(RX$weights)[[nm]]; s <- rx_score_with(w)
  q <- select_units(CU, s); cl <- if (is.null(q)) integer() else unlist(lapply(q$cid, function(i) cand[[i]]$cells))
  data.frame(scenario = nm, rx_cell_jaccard = if (length(cl)) jac(cl, base_cells) else NA,
             rx_sites_within_500m = if (is.null(q)) NA else sum(apply(as.matrix(dist(rbind(SEL[, c("x", "y")], q[, c("x", "y")])))[seq_len(nrow(SEL)), nrow(SEL) + seq_len(nrow(q))], 1, min) < 500)) }))
print(SENS_FL); print(SENS_RX)

# =====================================================================================================================
# OUTPUT FILES
# =====================================================================================================================
gp <- file.path(OUTD, "fire_management_thimphu.gpkg"); if (file.exists(gp)) file.remove(gp)
st_write(LS, gp, "fire_lines_segmented", quiet = TRUE); if (CONT_OK) st_write(LC, gp, "fire_lines_continuous", quiet = TRUE)
LAYERS <- c("fire_lines_segmented", if (CONT_OK) "fire_lines_continuous", "rx_burn_sites")
if (!CONT_OK) unlink(c(file.path(OUTD, paste0("fire_lines_continuous", c(".kml", ".gpx"))), file.path(OUTD, "shp", paste0("fire_lines_continuous", c(".shp", ".shx", ".dbf", ".prj", ".cpg")))))
st_write(RXS, gp, "rx_burn_sites", quiet = TRUE)
pk <- pieces[, c("pid", "ring", "pos", "len_m", "feasible", "steep", "score", paste0("c_", COMP), "width_m", "wui_bld", "wui_bld_ob", "wui_bld_ncrp", "fire_n",
                 "slope_mean", "elev", "downslope_m", "veg_share", "road_share", "on_road_river", "anchor_start", "anchor_end", "in_pa",
                 "rank_feasible", "bld_dist_min", "bld_dist_med", "c_fuel", "on_private", "on_water_source", "in_jdwnp", "in_nogo", "walk_h")]
pk$selected_segmented <- pk$pid %in% base_seg; pk$selected_continuous <- pk$pid %in% base_con
st_write(pk, gp, "candidate_line_pieces", quiet = TRUE)
for (nm in LAYERS) {
  x <- st_transform(st_read(gp, nm, quiet = TRUE), 4326); key <- if ("segment" %in% names(x)) "segment" else "site"
  x$name <- x[[key]]
  x$description <- if (key == "segment") sprintf("%s | %s | %d m | %s | WUI bldgs %d", x$gewog, x$nearest_village, x$built_length_m, x$width_m_mix, x$wui_buildings_200m)
                   else sprintf("%s | %s | %.2f ha | %s | slope %.0f deg", x$gewog, x$nearest_village, x$area_ha, x$forest_type, x$slope_mean_deg)
  for (ext in c(".kml", ".gpx")) unlink(file.path(OUTD, paste0(nm, ext)))
  st_write(x[, c("name", "description")], file.path(OUTD, paste0(nm, ".kml")), driver = "KML", quiet = TRUE)
  gx <- if (key == "segment") st_cast(st_cast(x[, "name"], "MULTILINESTRING"), "LINESTRING", warn = FALSE) else st_cast(st_cast(x[, "name"], "MULTIPOLYGON"), "POLYGON", warn = FALSE) |> st_cast("LINESTRING", warn = FALSE)
  st_write(gx, file.path(OUTD, paste0(nm, ".gpx")), driver = "GPX", layer = "tracks", quiet = TRUE, dataset_options = "GPX_USE_EXTENSIONS=NO")
}
# shapefiles (EPSG:5266, DRUKREF 03 / Bhutan National Grid); field names are cut to 10 characters, full names in the CSV tables
SHP <- file.path(OUTD, "shp"); dir.create(SHP, showWarnings = FALSE)
for (nm in LAYERS) {
  unlink(file.path(SHP, paste0(nm, c(".shp", ".shx", ".dbf", ".prj", ".cpg"))))
  x <- st_read(gp, nm, quiet = TRUE)
  st_write(x, file.path(SHP, paste0(nm, ".shp")), quiet = TRUE, layer_options = "ENCODING=UTF-8")
}
# boundaries for field use: dzongkhag and gewogs (KML in WGS84, shapefile in EPSG:5266)
bnd <- list(thimphu_dzongkhag = st_sf(name = "Thimphu Dzongkhag", description = sprintf("Area %.1f km2", as.numeric(st_area(dz)) / 1e6), geometry = st_geometry(dz)),
            thimphu_gewogs = { x <- gw[gw$gewog != CFG$study_area$unassigned_unit, ]
              st_sf(name = x$gewog, description = sprintf("%s gewog, Thimphu | %.1f km2", x$gewog, as.numeric(st_area(x)) / 1e6), geometry = st_geometry(x)) })
for (nm in names(bnd)) {
  unlink(c(file.path(OUTD, paste0(nm, ".kml")), file.path(SHP, paste0(nm, c(".shp", ".shx", ".dbf", ".prj", ".cpg")))))
  st_write(bnd[[nm]], file.path(SHP, paste0(nm, ".shp")), quiet = TRUE, layer_options = "ENCODING=UTF-8")
  st_write(st_transform(bnd[[nm]], 4326), file.path(OUTD, paste0(nm, ".kml")), driver = "KML", quiet = TRUE)
}
# ---- exclusion layers (criteria section 4, outputs 5 and 7) -----------------------------------------------------------
message("D. exclusion layers")
dzg <- st_geometry(dz)
mk <- function(geom, group, constraint, applies_to, rule) {
  if (!length(geom)) return(NULL)
  geom <- st_union(st_make_valid(geom)); geom <- suppressWarnings(st_intersection(geom, dzg))
  if (!length(geom) || all(st_is_empty(geom))) return(NULL)
  geom <- st_make_valid(st_simplify(geom, dTolerance = 2))
  st_sf(group = group, constraint = constraint, applies_to = applies_to, rule = rule, area_ha = round(sum(as.numeric(st_area(geom))) / 1e4, 1), geometry = st_union(geom))
}
mask_poly <- function(lg) { lg <- !is.na(lg) & lg & inth; if (!any(lg)) return(st_sfc(crs = CRS))
  r <- setValues(rast(g), ifelse(lg, 1, NA)); st_set_crs(st_union(st_geometry(st_as_sf(as.polygons(r, dissolve = TRUE)))), CRS) }
EXL <- list(
  environmental = rbind(
    mk(ex_parts$stream, "environmental", "Stream buffer 15 m", "fire lines", "FL-12"),
    mk(ex_parts$river, "environmental", "Major river buffer 30 m", "fire lines", "FL-13"),
    mk(ex_parts$water_source, "environmental", "Drinking-water source buffer 10 m", "fire lines", "FL-14"),
    mk(st_geometry(pa[pa$park %in% FL$excluded_pa, ]), "environmental", "JDWNP (excluded)", "fire lines", "FL-16"),
    mk(st_buffer(st_geometry(streams), RX$stream_buffer_m, nQuadSegs = 2), "environmental", "Stream and river buffer 30 m", "prescribed burning", "RX-13"),
    mk(st_buffer(st_geometry(wsrc), RX$water_source_buffer_m, nQuadSegs = 6), "environmental", "Water source buffer 100 m", "prescribed burning", "RX-14"),
    mk(st_geometry(pa[grepl("Corridor", pa$park), ]), "environmental", "Biological corridor (flag, not excluded)", "both", "RX-18"),
    mk(st_geometry(pa[pa$park %in% c("Jigme Dorji Wangchuch National Park", "Royal Botanical Park"), ]), "environmental", "JDWNP / RBP (flag only for burning)", "prescribed burning", "RX-17")),
  infrastructure = rbind(
    mk(ex_parts$road, "infrastructure", "Road buffer 15 m (national + OSM motor roads/tracks)", "fire lines", "FL-11"),
    mk(st_buffer(bld_geom, FL$building_distance_m[1], nQuadSegs = 3), "infrastructure", "Within 30 m of a building", "fire lines", "FL-3"),
    mk(st_buffer(bld_geom, RX$min_building_m, nQuadSegs = 3), "infrastructure", "Within 150 m of a building", "prescribed burning", "RX-9")),
  land_use = rbind(
    mk(st_geometry(nogo), "land use", "Existing plantation / reserved or proposed site", "both", "FL-18 / RX-20"),
    mk(st_buffer(st_geometry(nogo), NGC$rx_buffer_m), "land use", "Plantation / reserved site + 50 m margin", "prescribed burning", "RX-20"),
    mk(st_geometry(pl), "land use", "Registered private land", "both", "FL-4 / RX-16"),
    mk(mask_poly((C$crop + C$built) >= 20), "land use", "Cropland or built-up >= 20% of cell", "prescribed burning", "RX-1"),
    mk(mask_poly(C$recent > 0), "land use", "Burned since 2023 (flag, not excluded)", "prescribed burning", "RX-15")),
  terrain_vegetation = rbind(
    mk(mask_poly(C$slope > FL$max_slope_deg), "terrain", "Slope > 30 deg", "fire lines", "FL-10"),
    mk(mask_poly(C$slope > RX$max_slope_deg), "terrain", "Slope > 25 deg", "prescribed burning", "RX-6"),
    mk(mask_poly(C$elev < RX$elev_m[1] | C$elev > RX$elev_m[2]), "terrain", "Outside 2000-3300 m", "prescribed burning", "RX-5"),
    mk(mask_poly(C$bare > RX$max_bare_pct), "vegetation", "Bare or sparse > 20%", "prescribed burning", "RX-7"),
    mk(mask_poly(C$ft %in% RX$excluded_forest_types), "vegetation", "Fir, hemlock, spruce, broadleaf or alpine scrub", "prescribed burning", "RX-4"),
    mk(mask_poly(!C$soil_ok), "soil", "Soil unsuitable for planting", "prescribed burning", "RX-8")))
EXL <- EXL[!vapply(EXL, is.null, TRUE)]
gx_ex <- file.path(OUTD, "exclusion_layers.gpkg"); if (file.exists(gx_ex)) file.remove(gx_ex)
for (nm in names(EXL)) {
  x <- EXL[[nm]]; lay_nm <- paste0("excl_", nm); st_write(x, gx_ex, lay_nm, quiet = TRUE)
  unlink(c(file.path(OUTD, paste0(lay_nm, ".kml")), file.path(SHP, paste0(lay_nm, c(".shp", ".shx", ".dbf", ".prj", ".cpg")))))
  st_write(x, file.path(SHP, paste0(lay_nm, ".shp")), quiet = TRUE, layer_options = "ENCODING=UTF-8")
  k <- st_transform(x, 4326); k$name <- k$constraint; k$description <- sprintf("%s | %s | %s | %.0f ha in Thimphu", k$group, k$applies_to, k$rule, k$area_ha)
  st_write(k[, c("name", "description")], file.path(OUTD, paste0(lay_nm, ".kml")), driver = "KML", quiet = TRUE)
}
exclusion_summary <- do.call(rbind, lapply(EXL, st_drop_geometry))

# ---- prescribed-burn suitability surface (output 2) -------------------------------------------------------------------
sv <- rep(NA_real_, ncell(g)); sv[SUIT$cell] <- SUIT$score; suit_r <- setValues(rast(g), sv); names(suit_r) <- "rx_suitability"
writeRaster(suit_r, file.path(OUTD, "rx_suitability_50m.tif"), overwrite = TRUE, gdal = "COMPRESS=DEFLATE")
qs <- quantile(SUIT$score, c(1 / 3, 2 / 3))
SUIT$class <- cut(SUIT$score, c(-Inf, qs, Inf), labels = c("Low", "Moderate", "High"))
cr <- rep(NA, ncell(g)); cr[SUIT$cell] <- as.integer(SUIT$class)
sp_cls <- st_as_sf(as.polygons(setValues(rast(g), cr), dissolve = TRUE)); names(sp_cls)[1] <- "class_id"
sp_cls <- st_set_crs(sp_cls, CRS); sp_cls$class <- c("Low", "Moderate", "High")[sp_cls$class_id]
sp_cls$area_ha <- round(as.numeric(st_area(sp_cls)) / 1e4, 1)
sp_cls$score_range <- c(sprintf("%.2f-%.2f", min(SUIT$score), qs[1]), sprintf("%.2f-%.2f", qs[1], qs[2]), sprintf("%.2f-%.2f", qs[2], max(SUIT$score)))[sp_cls$class_id]
st_write(sp_cls, gp, "rx_suitability_classes", quiet = TRUE, append = FALSE)
unlink(c(file.path(OUTD, "rx_suitability_classes.kml"), file.path(SHP, paste0("rx_suitability_classes", c(".shp", ".shx", ".dbf", ".prj", ".cpg")))))
st_write(sp_cls, file.path(SHP, "rx_suitability_classes.shp"), quiet = TRUE)
k <- st_transform(sp_cls, 4326); k$name <- paste(k$class, "suitability"); k$description <- sprintf("Score %s | %.1f ha eligible", k$score_range, k$area_ha)
st_write(k[, c("name", "description")], file.path(OUTD, "rx_suitability_classes.kml"), driver = "KML", quiet = TRUE)

# ---- scores and rankings for all candidates (output 4) -------------------------------------------------------------------
fp_mid <- st_cast(st_line_sample(st_geometry(pieces), sample = 0.5), "POINT"); llp <- wgs(fp_mid)
rank_pieces <- data.frame(st_drop_geometry(pieces)[, c("pid", "ring", "pos", "len_m", "feasible", "rank_feasible", "score", paste0("c_", COMP), "width_m",
                                                    "wui_bld", "bld_dist_min", "bld_dist_med", "veg_share", "slope_mean", "elev", "walk_h", "fire_n",
                                                    "anchor_start", "anchor_end", "on_private", "on_road", "on_stream_river", "on_water_source", "in_jdwnp", "in_nogo")],
                          gewog = unit_of(fp_mid), mid_lon = llp[, 1], mid_lat = llp[, 2])
rank_pieces$fails <- apply(sapply(FRULES, function(x) !x), 1, function(z) paste(names(FRULES)[z], collapse = "; "))
rank_pieces$selected_segmented <- rank_pieces$pid %in% unlist(segA); rank_pieces$selected_continuous <- rank_pieces$pid %in% conA
rank_pieces <- rank_pieces[order(is.na(rank_pieces$rank_feasible), rank_pieces$rank_feasible), ]
llc <- round(st_coordinates(st_transform(st_as_sf(CU, coords = c("x", "y"), crs = CRS), 4326)), 6)
rank_units <- data.frame(CU[, c("rank", "cid", "seed", "gewog", "ha", "score", "score_cells", "fuel_index", "hold")], centroid_lon = llc[, 1], centroid_lat = llc[, 2],
                         selected = CU$cid %in% SEL$cid)
rank_units <- rank_units[order(rank_units$rank), ]
names(rank_units)[names(rank_units) == "hold"] <- "holding_edge_share"

# ---- comparative table of selected sites (output 6) ------------------------------------------------------------------------
cmp_fl <- function(x) data.frame(id = x$segment, type = paste("Fire line,", x$option), gewog = x$gewog, nearest_village = x$nearest_village,
  lon = round((x$start_lon + x$end_lon) / 2, 5), lat = round((x$start_lat + x$end_lat) / 2, 5), size = sprintf("%d m (%.2f ha cleared)", x$built_length_m, x$cleared_ha),
  width_m = x$width_m_mix, elevation_m = sprintf("%d-%d", x$elev_min_m, x$elev_max_m), slope_mean_deg = x$slope_mean_deg, fuel_index = x$fuel_index,
  access_walk_h = x$walk_h_mean, anchored_both_ends = x$anchored_start & x$anchored_end, nearest_building_m = x$nearest_building_m,
  wui_buildings = sprintf("%d within 200 m", x$wui_buildings_200m), score = x$score_mean, flags = ifelse(x$protected_area_flag == "none", "", x$protected_area_flag))
cmp_rx <- function(x) data.frame(id = x$site, type = "Prescribed burn", gewog = x$gewog, nearest_village = x$nearest_village, lon = x$centroid_lon, lat = x$centroid_lat,
  size = sprintf("%.2f ha", x$area_ha), width_m = "", elevation_m = sprintf("%d-%d", x$elev_min_m, x$elev_max_m), slope_mean_deg = x$slope_mean_deg,
  fuel_index = x$fuel_index, access_walk_h = x$walk_h_mean, anchored_both_ends = NA, nearest_building_m = x$nearest_building_m,
  wui_buildings = sprintf("%d within 500 m", x$wui_buildings_500m), score = x$score,
  flags = trimws(gsub(" +", " ", paste(ifelse(x$protected_area_flag != "none", x$protected_area_flag, ""),
                                       ifelse(x$burned_since_2023_pct > 0, sprintf("burned since 2023 (%d%%)", x$burned_since_2023_pct), ""),
                                       ifelse(!x$holding_ge_50pct, sprintf("holding edge %d%%", round(100 * x$holding_edge_share)), "")))))
COMPARE <- rbind(cmp_fl(st_drop_geometry(LS)), if (CONT_OK) cmp_fl(st_drop_geometry(LC)), cmp_rx(st_drop_geometry(RXS)))
write.csv(COMPARE, file.path(OUTD, "comparative_selected_sites.csv"), row.names = FALSE)
write.csv(rank_pieces, file.path(OUTD, "ranking_fire_line_pieces.csv"), row.names = FALSE)
write.csv(rank_units, file.path(OUTD, "ranking_rx_candidate_units.csv"), row.names = FALSE)
write.csv(funnel_fl, file.path(OUTD, "fire_line_exclusion_funnel.csv"), row.names = FALSE)
write.csv(exclusion_summary, file.path(OUTD, "exclusion_layers_summary.csv"), row.names = FALSE)
TL <- rbind(st_drop_geometry(LS), if (CONT_OK) st_drop_geometry(LC))
write.csv(TL, file.path(OUTD, "fire_lines_table.csv"), row.names = FALSE)
write.csv(st_drop_geometry(RXS), file.path(OUTD, "rx_burn_sites_table.csv"), row.names = FALSE)
write.csv(funnel, file.path(OUTD, "rx_eligibility_funnel.csv"), row.names = FALSE)
write.csv(SENS_FL, file.path(OUTD, "sensitivity_fire_lines.csv"), row.names = FALSE)
write.csv(SENS_RX, file.path(OUTD, "sensitivity_rx_sites.csv"), row.names = FALSE)
saveRDS(list(pieces = pieces, LS = LS, LC = LC, RXS = RXS, SEL = SEL, CU = CU, funnel = funnel, SENS_FL = SENS_FL, SENS_RX = SENS_RX,
             E = E[, c("cell", "score", "gewog")], RC = RC, SUIT = SUIT, funnel_fl = funnel_fl, COMPARE = COMPARE, exclusion_summary = exclusion_summary, qs = qs, cand_cells = lapply(SEL$cid, function(i) cand[[i]]$cells), segA = segA, conA = conA, CONT_OK = CONT_OK, CONT_MAX_M = CONT_MAX_M), file.path(OUTD, "run_state.rds"))
message("Spatial outputs: ", OUTD)
