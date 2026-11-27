# 04  Field design (v1.1): (A) CBI calibration plots and (B) an independent probability sample for map accuracy
# Reviewer R3-1: calibration and validation need separate samples.
#  (A) CALIBRATION plots fit the RBR-CBI relationship: stratified by provisional spectral-change class (and unburned
#      land 100-500 m outside patches), equal allocation, 20 primary + 5 reserve per stratum; centres in near-pure 3x3
#      neighbourhoods (>= 7 of 9 pixels, >= 5 of 9 for the thin low class), slope <= 40 deg, walk <= 2 h, >= 90 m apart;
#      most recent fires (priority years) first. Purity filters make these plots unsuitable for accuracy estimation.
#  (B) ACCURACY sample estimates map accuracy and error-adjusted area: stratified random by mapped class over ALL mapped
#      incidents' windows (no purity or slope filter), fixed n per stratum, inclusion probability recorded per point;
#      target population = mapped windows within 2 h walk of a road (stated, because inaccessible terrain is excluded).
# Both components record fire date and months between fire and the planned field season start.
# Outputs: data/derived/field_plan/ (gpkg, csv, gpx, blank forms) and docs/CBI_FIELD_PROTOCOL.md (written separately).
# Run: Rscript thimphu_paro_burn_severity/scripts/04_cbi_field_plan.R   (after 02)
source(if (file.exists("thimphu_paro_burn_severity/R/tp_common.R")) "thimphu_paro_burn_severity/R/tp_common.R" else "R/tp_common.R")
source(tp("R/sci_figure.R")); suppressPackageStartupMessages({ library(patchwork) })
set.seed(20261124)
# ============================================================
# CONFIGURATION
# ============================================================
FP <- CFG$field_plan
SLUG <- "03-cbi-plan"
TITLE <- "Field design: CBI calibration plots and independent accuracy sample, Paro and Thimphu"
GP <- tp("data/derived/burn_severity_paro_thimphu.gpkg"); OUT <- tp("data/derived/field_plan")
N_TOTAL <- ceiling(FP$plots_per_class * (1 + FP$reserve_fraction)); SEASON <- as.Date(FP$field_season_start)
# ============================================================
unlink(file.path(SCI_OUT_ROOT, SLUG), recursive = TRUE)
run <- sci_run(SLUG, TITLE, inputs = c(GP, tp("data/inputs/x")))
unlink(OUT, recursive = TRUE); dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
ip <- st_read(GP, "incident_points", quiet = TRUE); ip <- ip[ip$map_status == "Mapped", ]; ip$year <- as.integer(substr(ip$start_date_local, 1, 4))
dem <- rast(tp("data/inputs/dem_30m.tif")); slope_all <- terrain(dem, "slope", unit = "degrees"); walk <- rast(tp("data/inputs/walk_time_to_road_h_100m.tif"))
tier <- function(y) ifelse(y %in% FP$priority_years, "1 priority", ifelse(y >= min(FP$priority_years) - 1, "2 acceptable", "3 fallback (older fire)"))
months_since <- function(fd) round(as.numeric(SEASON - as.Date(fd)) / 30.44, 1)

cand <- list(); acc_pop <- list()
for (i in seq_len(nrow(ip))) {
  key <- paste(ip$event_id[i], ip$sensor_used[i], sep = "_")
  cl <- rast(tp("data/derived/severity_rasters", paste0(key, "_severity.tif"))); levels(cl) <- NULL; v <- values(cl, mat = FALSE)
  hom <- focal(cl, 3, fun = function(x) if (is.na(x[5])) NA else sum(x == x[5], na.rm = TRUE), expand = FALSE)
  burned <- cl; burned[burned == 0] <- NA; dist_b <- distance(burned)
  sl <- resample(crop(slope_all, ext(cl) + 100), cl, "bilinear"); wk <- resample(crop(walk, ext(cl) + 200), cl, "bilinear")
  d <- data.frame(cell = seq_len(ncell(cl)), cls = v, hom = values(hom, mat = FALSE), dist_burn = values(dist_b, mat = FALSE), slope = values(sl, mat = FALSE), walk_h = values(wk, mat = FALSE))
  xy <- xyFromCell(cl, d$cell); d$x <- xy[, 1]; d$y <- xy[, 2]
  base <- data.frame(event_id = ip$event_id[i], sensor = ip$sensor_used[i], fire_date = ip$start_date_local[i], year = ip$year[i], dzongkhag = ip$dzongkhag[i])
  # (B) accuracy population: every mapped pixel + unburned pixels <= 500 m from patches, accessible (walk <= 2 h)
  a <- d[which(!is.na(d$cls) & d$walk_h <= FP$max_walk_time_h & (d$cls > 0 | d$dist_burn <= FP$unburned_buffer_m[2])), ]
  if (nrow(a)) acc_pop[[key]] <- cbind(base[rep(1, nrow(a)), ], stratum = SEV_LEVELS[a$cls + 1], x = a$x, y = a$y, walk_time_h = a$walk_h, px_ha = prod(res(cl)) / 1e4)
  # (A) calibration candidates
  need <- ifelse(d$cls == 1, FP$min_same_neighbours_low, FP$min_same_neighbours)
  c1 <- d[which(!is.na(d$cls) & d$hom >= need & d$slope <= FP$max_slope_deg & d$walk_h <= FP$max_walk_time_h), ]
  c1 <- c1[which(c1$cls > 0 | (c1$dist_burn >= FP$unburned_buffer_m[1] & c1$dist_burn <= FP$unburned_buffer_m[2])), ]
  if (nrow(c1)) cand[[key]] <- cbind(base[rep(1, nrow(c1)), ], stratum = SEV_LEVELS[c1$cls + 1], x = c1$x, y = c1$y, slope_deg = c1$slope, walk_time_h = c1$walk_h,
                                     neighbourhood_purity = c1$hom / 9, tier = tier(ip$year[i]))
}
CA <- do.call(rbind, cand); AP <- do.call(rbind, acc_pop)
CA$elevation_m <- extract(dem, as.matrix(CA[, c("x", "y")]))[, 1]

# ---- (A) calibration plots: priority tier first, round robin across fires, >= min spacing ----------------------------------
sel <- CA[0, ]
far <- function(S, x, y, d) !nrow(S) || all(sqrt((S$x - x)^2 + (S$y - y)^2) >= d)
for (st in SEV_LEVELS) { pool <- CA[CA$stratum == st, ]; pool <- pool[sample(nrow(pool)), ]
  pool <- pool[order(pool$tier, ave(seq_len(nrow(pool)), pool$event_id, FUN = seq_along)), ]; n <- 0
  for (j in seq_len(nrow(pool))) { if (n >= N_TOTAL) break; if (!far(sel, pool$x[j], pool$y[j], FP$min_spacing_m)) next; sel <- rbind(sel, pool[j, ]); n <- n + 1 } }
sel$stratum <- factor(sel$stratum, SEV_LEVELS); sel <- sel[order(sel$stratum, sel$tier), ]
sel$role <- ave(seq_len(nrow(sel)), sel$stratum, FUN = function(i) ifelse(seq_along(i) <= FP$plots_per_class, "primary", "reserve"))
sel$plot_id <- sprintf("CAL-%s-%02d", SEV_SHORT[as.integer(sel$stratum)], ave(seq_len(nrow(sel)), sel$stratum, FUN = seq_along))
sel$months_fire_to_field <- months_since(sel$fire_date); sel$component <- "A calibration"

# ---- (B) probability accuracy sample: stratified random, fixed n per stratum, inclusion probabilities ------------------------------
NH <- table(factor(AP$stratum, SEV_LEVELS))
acc <- do.call(rbind, lapply(SEV_LEVELS, function(st) { pool <- AP[AP$stratum == st, ]; n <- min(FP$accuracy_sample_per_class, nrow(pool))
  if (!n) return(NULL); s <- pool[sample(nrow(pool), n), ]; s$inclusion_probability <- n / nrow(pool); s$stratum_pixels <- nrow(pool); s$stratum_area_ha <- sum(pool$px_ha); s }))
acc$stratum <- factor(acc$stratum, SEV_LEVELS); acc <- acc[order(acc$stratum), ]
acc$plot_id <- sprintf("ACC-%s-%02d", SEV_SHORT[as.integer(acc$stratum)], ave(seq_len(nrow(acc)), acc$stratum, FUN = seq_along))
acc$months_fire_to_field <- months_since(acc$fire_date); acc$component <- "B accuracy (probability sample)"
acc$too_close_to_other_point_m <- vapply(seq_len(nrow(acc)), function(i) min(sqrt((acc$x[-i] - acc$x[i])^2 + (acc$y[-i] - acc$y[i])^2)), 0)

# ---- outputs ----------------------------------------------------------------------------------------------------------------
to_sf <- function(d) { s <- st_as_sf(d, coords = c("x", "y"), crs = CRS, remove = FALSE); ll <- st_coordinates(st_transform(s, 4326)); s$longitude <- round(ll[, 1], 6); s$latitude <- round(ll[, 2], 6); s }
sA <- to_sf(sel); sB <- to_sf(acc)
colsA <- c("plot_id", "component", "role", "stratum", "event_id", "fire_date", "months_fire_to_field", "dzongkhag", "sensor", "tier", "longitude", "latitude", "elevation_m", "slope_deg", "walk_time_h", "neighbourhood_purity")
colsB <- c("plot_id", "component", "stratum", "event_id", "fire_date", "months_fire_to_field", "dzongkhag", "sensor", "longitude", "latitude", "walk_time_h", "inclusion_probability", "stratum_pixels", "stratum_area_ha")
gp <- file.path(OUT, "field_design_paro_thimphu.gpkg")
st_write(sA[, colsA], gp, "A_calibration_plots", quiet = TRUE); st_write(sB[, colsB], gp, "B_accuracy_sample", quiet = TRUE, append = TRUE)
write.csv(st_drop_geometry(sA)[, colsA], file.path(OUT, "A_calibration_plots.csv"), row.names = FALSE)
write.csv(st_drop_geometry(sB)[, colsB], file.path(OUT, "B_accuracy_sample.csv"), row.names = FALSE)
gpx <- rbind(st_transform(sA, 4326)[, "plot_id"], st_transform(sB, 4326)[, "plot_id"]); names(gpx)[names(gpx) == "plot_id"] <- "name"
st_write(gpx, file.path(OUT, "field_design_paro_thimphu.gpx"), driver = "GPX", layer = "waypoints", quiet = TRUE, dataset_options = "GPX_USE_EXTENSIONS=NO")
ecol <- c("tree_count_in_plot", "trees_alive", "trees_dead_fire", "crown_scorch_pct", "bark_char_height_m", "regeneration_seedlings_per_m2", "ground_layer_cover_pct",
          "litter_consumed_pct", "duff_consumed_pct", "dominant_species", "stand_structure", "evidence_type_current_or_reconstructed")
formA <- data.frame(observation_id = sA$plot_id, event_id = sA$event_id, sample_date = "", longitude = sA$longitude, latitude = sA$latitude, cbi = "", reference_class = "", observer = "",
                    source_id = "paro_thimphu_cbi_2027", quality_flag = "", planned_stratum = sA$stratum, role = sA$role, months_fire_to_field = sA$months_fire_to_field, gps_error_m = "",
                    A_substrate = "", B_lt1m = "", B_cover_pct = "", C_1to5m = "", C_cover_pct = "", D_5to20m = "", D_cover_pct = "", E_gt20m = "", E_cover_pct = "",
                    understorey_cbi = "", overstorey_cbi = "", photos = "", notes = "")
for (k in ecol) formA[[k]] <- ""
write.csv(formA, file.path(OUT, "A_calibration_form_blank.csv"), row.names = FALSE, na = "")
formB <- data.frame(observation_id = sB$plot_id, longitude = sB$longitude, latitude = sB$latitude, sample_date = "", observer = "", gps_error_m = "",
                    burned_yes_no = "", observed_class_none_low_moderate_high = "", cbi_if_measured = "", confidence_1to3 = "", photos = "", notes = "")
write.csv(formB, file.path(OUT, "B_accuracy_form_blank.csv"), row.names = FALSE, na = "")

# ============================================================
# DATA HEALTH, FIGURES
# ============================================================
data_health(run, st_drop_geometry(sA)[, c("stratum", "role", "tier", "months_fire_to_field", "slope_deg", "walk_time_h", "neighbourhood_purity")], "(A) calibration plots")
data_health(run, st_drop_geometry(sB)[, c("stratum", "months_fire_to_field", "walk_time_h", "inclusion_probability")], "(B) accuracy sample")
short <- names(which(table(sel$stratum[sel$role == "primary"]) < FP$plots_per_class))
write_health(run, notes = c(
  sprintf("(A) %d calibration plots: %d primary + %d reserve on %d fires; candidates per stratum: %s.", nrow(sel), sum(sel$role == "primary"), sum(sel$role == "reserve"),
          length(unique(sel$event_id)), paste(names(table(CA$stratum)), as.integer(table(CA$stratum)), collapse = ", ")),
  sprintf("(B) %d accuracy points over %d mapped incidents; accessible population per stratum (pixels): %s.", nrow(acc), length(unique(AP$event_id)), paste(names(NH), as.integer(NH), collapse = ", ")),
  sprintf("Field season assumed to start %s; months from fire to field visit range %.1f-%.1f (A) and %.1f-%.1f (B).", SEASON, min(sel$months_fire_to_field), max(sel$months_fire_to_field),
          min(acc$months_fire_to_field), max(acc$months_fire_to_field)),
  "Calibration plots are chosen in near-pure neighbourhoods and are NOT used for accuracy; accuracy uses only the probability sample, weighted by inclusion probability (Olofsson et al. 2014)."))

dz <- study_dzongkhags()
both <- rbind(data.frame(st_drop_geometry(sA)[, c("x", "y", "stratum")], component = paste0("A calibration (", sel$role, ")")), data.frame(st_drop_geometry(sB)[, c("x", "y", "stratum")], component = "B accuracy"))
p1 <- ggplot() + geom_sf(data = dz, fill = NA, colour = "black", linewidth = 0.5) +
  geom_point(data = both, aes(x, y, colour = stratum, shape = component), size = 1.3) +
  scale_colour_manual(values = SEV_COLS |> replace(1, "#555555"), name = "Stratum") + scale_shape_manual(values = c(`A calibration (primary)` = 16, `A calibration (reserve)` = 1, `B accuracy` = 4), name = NULL) +
  ggspatial::annotation_scale(location = "bl", text_family = SCI$font, height = unit(0.15, "cm")) + theme_sci_map() + theme(legend.position = "right")
save_fig(run, p1, 1, "field_design_map", as.data.frame(table(component = both$component, stratum = both$stratum)), c(
  sprintf("Field design for Paro and Thimphu: (A) %d CBI calibration plots (%d primary, %d reserve) and (B) %d points of an independent probability sample for map accuracy.",
          nrow(sel), sum(sel$role == "primary"), sum(sel$role == "reserve"), nrow(acc)),
  sprintf("(A) stratified by provisional spectral-change class in near-pure neighbourhoods, slope <= %d deg, walk <= %g h, >= %d m apart, priority fires first; (B) stratified random over all mapped incident windows within %g h walk, no purity filter, inclusion probabilities recorded.",
          FP$max_slope_deg, FP$max_walk_time_h, FP$min_spacing_m, FP$max_walk_time_h),
  "Keeping the two samples separate lets the RBR-CBI thresholds be fitted on (A) and their map accuracy and error-adjusted area be estimated without bias from (B)."), size = c(6.5, 5.6))
mt <- rbind(data.frame(component = "A calibration", months = sel$months_fire_to_field), data.frame(component = "B accuracy", months = acc$months_fire_to_field))
p2 <- ggplot(mt, aes(months)) + geom_histogram(binwidth = 3, fill = "#bbbbbb", colour = "black", linewidth = 0.25, boundary = 0) + facet_wrap(~ component, ncol = 1, scales = "free_y") +
  geom_vline(xintercept = c(9, 12), linetype = "dashed") + labs(x = sprintf("Months from fire to field season start (%s)", format(SEASON, "%d %b %Y")), y = "Plots (count)") + theme_sci()
save_fig(run, p2, 2, "months_fire_to_field", mt, c(
  "Elapsed time between each sampled fire and the planned field season, by sample component.",
  "Months from the DoFPS reported start date to the assumed start of fieldwork; dashed lines mark the 9-12 month extended-assessment window of Key & Benson (2006).",
  sprintf("Calibration plots fall %.1f-%.1f months after their fires, so %s; the elapsed time of every plot is recorded and will enter the RBR-CBI model as a covariate.",
          min(sel$months_fire_to_field), max(sel$months_fire_to_field),
          ifelse(max(sel$months_fire_to_field) > 15 | min(sel$months_fire_to_field) < 6, "not all match the ideal extended-assessment timing", "they match the extended-assessment timing"))), size = c(5.5, 4))
write_process(run, st_drop_geometry(sA)[, colsA], "A_calibration_plots"); write_process(run, st_drop_geometry(sB)[, colsB], "B_accuracy_sample")
write_process(run, as.data.frame(table(event_id = sel$event_id, stratum = sel$stratum, role = sel$role)) |> subset(Freq > 0), "A_plots_per_fire")
write_json_pretty(list(n_A = nrow(sel), n_A_primary = sum(sel$role == "primary"), n_A_reserve = sum(sel$role == "reserve"), n_A_fires = length(unique(sel$event_id)),
                       A_per_stratum = as.list(table(sel$stratum)), A_fire_years = sort(unique(sel$year)), A_months = range(sel$months_fire_to_field),
                       n_B = nrow(acc), n_B_incidents = length(unique(acc$event_id)), B_per_stratum = as.list(table(acc$stratum)), B_months = range(acc$months_fire_to_field),
                       field_season_start = as.character(SEASON), short_strata = short), tp("data/derived/results_field_plan.json"))
build_report(run, intro = c(
  sprintf("Two-component field design: (A) %d CBI calibration plots (%d primary + %d reserve, %d fires) and (B) %d-point independent probability sample for map accuracy and error-adjusted area.",
          nrow(sel), sum(sel$role == "primary"), sum(sel$role == "reserve"), length(unique(sel$event_id)), nrow(acc)),
  "See docs/CBI_FIELD_PROTOCOL.md for objectives, measurements and analysis."))
print(table(sel$stratum, sel$role)); print(table(acc$stratum))
