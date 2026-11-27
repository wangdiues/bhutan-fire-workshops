# 05  Exposure in the calibrated WUI of Thimphu, gewog priorities and a blind field validation kit
# Per building (Open Buildings V3, 2023): calibrated WUI class, fire evidence within 1 km (2012-2025), local fire
# susceptibility class (top classes 4-5 = high), walking time to the nearest road. Per gewog: WUI area, buildings,
# people (WorldPop 2020 constrained), fire-exposed and high-susceptibility WUI buildings, remote WUI buildings
# (> 1 h walk), OSM road length inside WUI, and a priority rank (mean rank of four exposure indicators).
# Field kit: stratified random 50 m cells per calibrated class (walk <= 2 h, >= 300 m apart); the class is withheld
# from the field file (blind) and kept in a separate key so observers are not biased.
# Run: Rscript thimphu_WUI/scripts/05_exposure_fieldkit.R   (after 03)
source(if (file.exists("thimphu_WUI/R/tw_common.R")) "thimphu_WUI/R/tw_common.R" else "R/tw_common.R")
source(tw("R/sci_figure.R")); suppressPackageStartupMessages({ library(patchwork) })
terraOptions(memfrac = 0.5, progress = 0)
set.seed(20261123)
# ============================================================
# CONFIGURATION
# ============================================================
SLUG <- "04-exposure"
TITLE <- "Exposure, priorities and field validation kit for the Thimphu wildland-urban interface"
EX <- CFG$exposure; FK <- CFG$field_kit; DMAIN <- CFG$fire_evidence$exposure_distance_m
OUTK <- tw("data/derived/field_kit")
# ============================================================
# Reuse the existing output tree; overwrite generated files without recreating folders.
run <- sci_run(SLUG, TITLE, inputs = c(tw("data/inputs/x"), tw("data/derived/x")))
dir.create(OUTK, showWarnings = FALSE, recursive = TRUE)
g <- grid50(); zone <- values(g, mat = FALSE); inside <- which(zone %in% 2); km2 <- (RES / 1000)^2
gid <- rast(tw("data/inputs/gewog_50m.tif")); glev <- levels(gid)[[1]]
unit <- glev[[2]][match(values(gid, mat = FALSE), glev[[1]])][inside]; unit[is.na(unit)] <- CFG$study_area$unassigned_unit
cal_r <- rast(tw("data/derived/wui_class_calibrated_50m.tif")); cl <- values(cal_r, mat = FALSE)[inside]; wui <- cl %in% 1:2
pop <- values(rast(tw("data/inputs/population_2020_50m.tif")), mat = FALSE)[inside]; pop[is.na(pop)] <- 0
walk <- values(rast(tw("data/inputs/walk_time_h_50m.tif")), mat = FALSE)[inside]
sus <- values(rast(tw("data/inputs/susceptibility_class_50m.tif")), mat = FALSE)[inside]; high <- sus %in% EX$high_susceptibility_classes
# fire evidence distance per cell (same evidence as script 03)
fe <- tw("data/inputs/fire_evidence.gpkg")
evr <- cover(cover(rasterize(vect(st_read(fe, "dofps_points", quiet = TRUE)), g, field = 1),
                   rasterize(vect(st_read(fe, "burned_patches", quiet = TRUE)), g, field = 1, touches = TRUE)),
             rasterize(vect(st_read(fe, "firms_points", quiet = TRUE)), g, field = 1))
fire_near <- values(distance(evr), mat = FALSE)[inside] <= DMAIN
ob <- st_read(tw("data/derived/wui_thimphu.gpkg"), "buildings", quiet = TRUE)
bi <- match(cellFromXY(g, st_coordinates(ob)), inside)
ob$walk_h <- walk[bi]; ob$high_susceptibility <- high[bi]; ob$fire_within_1km <- ob$dist_fire_all_m <= DMAIN
ob$in_wui <- ob$class_calibrated %in% c("intermix", "interface")

# ---- gewog table ---------------------------------------------------------------------------------------------------------
roads <- st_read(tw("data/inputs/roads_osm.gpkg"), quiet = TRUE)
wpol <- st_union(st_read(tw("data/derived/wui_thimphu.gpkg"), "wui_classes_calibrated", quiet = TRUE) |> subset(class %in% c("intermix", "interface")))
rw <- suppressWarnings(st_intersection(roads, wpol)); rw$km <- as.numeric(st_length(rw)) / 1000
gw <- study_gewogs(); rw_u <- suppressWarnings(st_intersection(rw[, "km"], gw[, "gewog"])); rw_u$km <- as.numeric(st_length(rw_u)) / 1000
units <- sort(unique(unit))
GT <- do.call(rbind, lapply(units, function(u) { s <- unit == u; b <- ob[ob$unit == u, ]; bw <- b[b$in_wui, ]
  data.frame(unit = u, area_km2 = sum(s) * km2, wui_km2 = sum(wui[s]) * km2, intermix_km2 = sum(cl[s] %in% 1) * km2, interface_km2 = sum(cl[s] %in% 2) * km2,
             buildings = nrow(b), wui_buildings = nrow(bw), wui_building_share = if (nrow(b)) nrow(bw) / nrow(b) else NA,
             people = sum(pop[s]), wui_people = sum(pop[s & wui]),
             wui_fire_exposed_buildings = sum(bw$fire_within_1km), wui_high_susceptibility_buildings = sum(bw$high_susceptibility, na.rm = TRUE),
             wui_exposed_and_high_buildings = sum(bw$fire_within_1km & bw$high_susceptibility, na.rm = TRUE),
             wui_remote_buildings = sum(bw$walk_h > EX$remote_walk_h, na.rm = TRUE), median_walk_h_wui = if (nrow(bw)) median(bw$walk_h, na.rm = TRUE) else NA,
             road_km_in_wui = sum(rw_u$km[rw_u$gewog == u])) }))
ind <- c("wui_buildings", "wui_fire_exposed_buildings", "wui_high_susceptibility_buildings", "wui_people")
GT <- GT[GT$buildings > 0 | GT$unit != CFG$study_area$unassigned_unit, ]   # boundary slivers with no buildings are dropped
GT$priority_score <- rowMeans(sapply(ind, function(v) rank(-GT[[v]], ties.method = "average")))
GT$priority_rank <- rank(GT$priority_score, ties.method = "first")
GT <- GT[order(GT$priority_rank), ]
write.csv(GT, tw("data/derived/exposure_by_gewog.csv"), row.names = FALSE)

# ---- priority map --------------------------------------------------------------------------------------------------------------
PR_LAB <- c("WUI: high susceptibility + fire within 1 km", "WUI: high susceptibility", "WUI: fire within 1 km", "WUI: other")
pr <- ifelse(!wui, NA_integer_, ifelse(high & fire_near, 1L, ifelse(high, 2L, ifelse(fire_near, 3L, 4L))))
fill <- function(v) { r <- rast(g); xx <- rep(NA_real_, ncell(g)); xx[inside] <- v; values(r) <- xx; r }
pr_r <- fill(pr); levels(pr_r) <- data.frame(value = 1:4, priority = PR_LAB)
writeRaster(pr_r, tw("data/derived/wui_priority_50m.tif"), overwrite = TRUE, datatype = "INT1U", gdal = "COMPRESS=DEFLATE")
gpk <- tw("data/derived/wui_thimphu.gpkg")
st_write(ob[, c("confidence", "area_m2", "unit", "class_calibrated", "class_baseline", "dist_fire_all_m", "fire_within_1km", "high_susceptibility", "walk_h", "in_wui")],
         gpk, "buildings", quiet = TRUE, delete_layer = TRUE)
gws <- merge(gw, GT, by.x = "gewog", by.y = "unit"); st_write(gws, gpk, "gewog_exposure", quiet = TRUE, delete_layer = TRUE)

# ---- blind field validation kit ------------------------------------------------------------------------------------------
xy <- xyFromCell(g, inside)
cand <- data.frame(cell = inside, x = xy[, 1], y = xy[, 2], class = CLASSES[cl], walk_h = walk)
cand <- cand[!is.na(cand$class) & !is.na(cand$walk_h) & cand$walk_h <= 2, ]
sel <- cand[0, ]
for (k in names(FK$points_per_class)) {
  pool <- cand[cand$class == k, ]; pool <- pool[sample(nrow(pool)), ]; n <- 0
  for (j in seq_len(nrow(pool))) { if (n >= FK$points_per_class[[k]]) break
    if (nrow(sel) && any(sqrt((sel$x - pool$x[j])^2 + (sel$y - pool$y[j])^2) < FK$min_spacing_m)) next
    sel <- rbind(sel, pool[j, ]); n <- n + 1 }
}
sel <- sel[sample(nrow(sel)), ]; sel$point_id <- sprintf("TW-%03d", seq_len(nrow(sel)))
sp <- st_as_sf(sel, coords = c("x", "y"), crs = CRS, remove = FALSE); ll <- st_coordinates(st_transform(sp, 4326))
sp$longitude <- round(ll[, 1], 6); sp$latitude <- round(ll[, 2], 6); sp$unit <- unit[match(sp$cell, inside)]
blind <- sp[, c("point_id", "longitude", "latitude", "unit", "walk_h")]
for (f in list.files(OUTK, full.names = TRUE)) file.remove(f)
st_write(blind, file.path(OUTK, "wui_validation_points_blind.gpkg"), quiet = TRUE)
bl <- st_transform(blind, 4326); bl$name <- bl$point_id; bl$description <- paste("Gewog:", bl$unit)
st_write(bl[, c("name", "description")], file.path(OUTK, "wui_validation_points_blind.kml"), driver = "KML", quiet = TRUE)
st_write(bl[, "name"], file.path(OUTK, "wui_validation_points_blind.gpx"), driver = "GPX", layer = "waypoints", quiet = TRUE, dataset_options = "GPX_USE_EXTENSIONS=NO")
write.csv(st_drop_geometry(sp)[, c("point_id", "class", "unit", "walk_h")], file.path(OUTK, "wui_validation_KEY_do_not_give_to_observers.csv"), row.names = FALSE)
form <- data.frame(point_id = sp$point_id, longitude = sp$longitude, latitude = sp$latitude, date = "", observer = "", gps_error_m = "",
                   buildings_within_250m = "", buildings_within_500m = "", wildland_cover_pct_within_250m = "", dominant_wildland_type = "",
                   distance_to_continuous_wildland_m = "", observer_class = "", confidence_1to3 = "", photos_N_E_S_W = "", notes = "")
# Keep the revised survey fields available even when documentation stage 09 is skipped.
review_fields <- c("observer_pair_id", "survey_objective", "sampling_stratum_id", "inclusion_probability", "design_weight",
  "target_access_status", "nonresponse_reason", "observation_longitude", "observation_latitude", "buildings_within_1000m",
  "count_source_250m", "count_source_500m", "count_source_1000m", "wildland_cover_pct_within_500m", "wildland_cover_pct_within_1000m",
  "vegetation_subtypes", "wildland_patch_id", "wildland_patch_area_km2", "wildland_continuity", "settlement_configuration",
  "fuel_pathways", "road_type_condition", "vehicle_access", "turning_space", "water_sources", "communications", "imagery_date", "reference_uncertainty")
for (field in setdiff(review_fields, names(form))) form[[field]] <- ""
write.csv(form, file.path(OUTK, "wui_validation_form_blank.csv"), row.names = FALSE, na = "")

# ============================================================
# DATA HEALTH
# ============================================================
data_health(run, GT[, c("wui_km2", "wui_buildings", "wui_people", "wui_fire_exposed_buildings", "wui_high_susceptibility_buildings", "wui_remote_buildings", "road_km_in_wui")], "Exposure by gewog / unit")
data_health(run, st_drop_geometry(ob)[ob$in_wui, c("walk_h", "dist_fire_all_m", "fire_within_1km", "high_susceptibility")], "Buildings in the calibrated WUI")
write_health(run, notes = c(
  sprintf("Population is WorldPop 2020 constrained (about 100 m, modelled, not census); %.0f people inside Thimphu after regridding.", sum(pop)),
  sprintf("High susceptibility = local susceptibility classes %s of the parent project's Paro-Thimphu model (top 15%% of cells); that model is itself fitted to fire history, so fire exposure and susceptibility are related but not identical.", paste(EX$high_susceptibility_classes, collapse = " and ")),
  sprintf("Field kit: %d points (%s); cells with walk time > 2 h excluded for safety and cost, so the validation describes accessible terrain; small classes cannot supply their targets at >= %d m spacing.",
          nrow(sp), paste(names(table(sp$class)), as.integer(table(sp$class)), collapse = ", "), FK$min_spacing_m),
  "WorldPop 2020 constrained places no people in some settled gewogs (e.g. Genye), so population in WUI is a lower bound; building counts are the more reliable exposure measure.",
  "Gewog priority = mean rank of WUI buildings, fire-exposed WUI buildings, high-susceptibility WUI buildings and WUI people; it is a screening order, not a risk model."))

# ============================================================
# FIGURES
# ============================================================
dz <- study_dz()
pd <- as.data.frame(mask(pr_r, vect(dz)), xy = TRUE, na.rm = TRUE); names(pd)[3] <- "priority"; pd$priority <- factor(pd$priority, PR_LAB)
p1 <- ggplot() + geom_sf(data = gw, fill = "#f4f4f4", colour = "#999999", linewidth = 0.25) + geom_raster(data = pd, aes(x, y, fill = priority)) +
  scale_fill_manual(values = setNames(c("#a50026", "#f46d43", "#fdae61", "#bbbbbb"), PR_LAB), name = NULL, drop = FALSE) +
  geom_sf(data = dz, fill = NA, colour = "black", linewidth = 0.5) + geom_sf_text(data = gw, aes(label = gewog), family = SCI$font, size = 2.4) +
  ggspatial::annotation_scale(location = "bl", text_family = SCI$font, height = unit(0.15, "cm")) + theme_sci_map() + theme(legend.position = "bottom") +
  guides(fill = guide_legend(ncol = 2))
pk <- c(sum(pr %in% 1), sum(pr %in% 2), sum(pr %in% 3), sum(pr %in% 4)) * km2
bk <- c(sum(ob$in_wui & ob$high_susceptibility & ob$fire_within_1km, na.rm = TRUE), sum(ob$in_wui & ob$high_susceptibility & !ob$fire_within_1km, na.rm = TRUE),
        sum(ob$in_wui & !ob$high_susceptibility & ob$fire_within_1km, na.rm = TRUE), sum(ob$in_wui & !ob$high_susceptibility & !ob$fire_within_1km, na.rm = TRUE))
save_fig(run, p1, 1, "wui_priority_map", data.frame(priority = PR_LAB, area_km2 = pk, buildings = bk), c(
  "Priority classes within the calibrated wildland-urban interface of Thimphu dzongkhag.",
  sprintf("WUI cells split by local fire susceptibility (classes %s = high) and fire evidence within %d m (2012-2025); grey background = non-WUI land.", paste(EX$high_susceptibility_classes, collapse = "-"), DMAIN),
  sprintf("%.1f km2 of WUI holding %s buildings combines high susceptibility with recent nearby fire, the first target for fuel breaks, defensible space and community preparedness.", pk[1], format(bk[1], big.mark = ","))),
  size = c(6.5, 6.8))

GL <- do.call(rbind, lapply(seq_len(nrow(GT)), function(i) data.frame(unit = GT$unit[i],
  group = c("High susceptibility + fire within 1 km", "High susceptibility only", "Fire within 1 km only", "Other WUI"),
  buildings = c(GT$wui_exposed_and_high_buildings[i], GT$wui_high_susceptibility_buildings[i] - GT$wui_exposed_and_high_buildings[i],
                GT$wui_fire_exposed_buildings[i] - GT$wui_exposed_and_high_buildings[i],
                GT$wui_buildings[i] - GT$wui_fire_exposed_buildings[i] - GT$wui_high_susceptibility_buildings[i] + GT$wui_exposed_and_high_buildings[i]))))
GL$unit <- factor(GL$unit, rev(GT$unit)); GL$group <- factor(GL$group, rev(unique(GL$group)))
p2 <- ggplot(GL, aes(buildings, unit, fill = group)) + geom_col(colour = "black", linewidth = 0.2, width = 0.7) +
  scale_fill_manual(values = c(`High susceptibility + fire within 1 km` = "#a50026", `High susceptibility only` = "#f46d43", `Fire within 1 km only` = "#fdae61", `Other WUI` = "#dddddd"),
                    name = NULL, breaks = levels(GL$group)[4:1]) +
  labs(x = "Buildings in the calibrated WUI (count)", y = NULL) + theme_sci() + theme(legend.position = "bottom") + guides(fill = guide_legend(ncol = 2))
save_fig(run, p2, 2, "wui_buildings_by_gewog", GT[, c("unit", "priority_rank", ind, "wui_exposed_and_high_buildings")], c(
  "Buildings in the calibrated WUI of Thimphu by gewog, split by fire susceptibility and nearby fire evidence.",
  "Gewogs ordered by priority rank (mean rank of WUI buildings, fire-exposed WUI buildings, high-susceptibility WUI buildings and WUI population).",
  sprintf("%s ranks first with %s WUI buildings, %s of them both highly susceptible and within 1 km of recent fire.", GT$unit[1], format(GT$wui_buildings[1], big.mark = ","), format(GT$wui_exposed_and_high_buildings[1], big.mark = ","))),
  size = c(6.5, 4.4))

pa <- ggplot(GT, aes(wui_people, factor(unit, rev(unit)))) + geom_col(fill = "#888888", colour = "black", linewidth = 0.2, width = 0.65) +
  labs(x = "People in WUI (WorldPop 2020)", y = NULL) + theme_sci()
pb <- ggplot(GT, aes(100 * wui_remote_buildings / pmax(1, wui_buildings), factor(unit, rev(unit)))) + geom_col(fill = "#ffffff", colour = "black", linewidth = 0.2, width = 0.65) +
  labs(x = sprintf("WUI buildings > %g h walk from a road (%%)", EX$remote_walk_h), y = NULL) + theme_sci() + theme(axis.text.y = element_blank())
p3 <- pa + pb + plot_annotation(tag_levels = "a", tag_prefix = "(", tag_suffix = ")") & theme(plot.tag = element_text(family = SCI$font, size = 10))
rem <- sum(GT$wui_remote_buildings) / sum(GT$wui_buildings)
save_fig(run, p3, 3, "people_and_access", GT[, c("unit", "wui_people", "wui_remote_buildings", "wui_buildings", "median_walk_h_wui", "road_km_in_wui")], c(
  "People living in the calibrated WUI of Thimphu by gewog (a) and the share of WUI buildings far from a road (b).",
  sprintf("Population: WorldPop 2020 constrained (modelled) summed over WUI cells; access: walking time to the nearest road from the parent project's accessibility layer; %.0f km of OSM road runs through the WUI.", sum(GT$road_km_in_wui)),
  sprintf("About %s people live in the WUI and %.0f%% of WUI buildings are more than %g h walk from a road, %s.", format(round(sum(GT$wui_people), -2), big.mark = ","), 100 * rem, EX$remote_walk_h,
          ifelse(rem < 0.10, "so road access reaches almost every WUI building and protection effort can concentrate on fuels, defensible space and preparedness",
                 "so suppression access, not only fuels, limits protection in the remote gewogs"))),
  size = c(7.2, 3.8))

p4 <- ggplot() + geom_sf(data = gw, fill = NA, colour = "#999999", linewidth = 0.25) + geom_sf(data = dz, fill = NA, colour = "black", linewidth = 0.5) +
  geom_sf(data = sp, aes(colour = factor(class, CLASSES)), size = 1.3) + scale_colour_manual(values = WUI_COLS, name = "Mapped class (key only)", drop = FALSE) +
  ggspatial::annotation_scale(location = "bl", text_family = SCI$font, height = unit(0.15, "cm")) + theme_sci_map() + theme(legend.position = "right")
save_fig(run, p4, 4, "field_validation_kit", as.data.frame(table(class = sp$class)), c(
  sprintf("Blind field validation sample for the calibrated WUI map of Thimphu (n = %d points).", nrow(sp)),
  sprintf("Stratified random 50 m cells per mapped class, walking time <= 2 h, >= %d m apart; drawn (target): %s; colours show the mapped class from the separate key, which observers do not receive.",
          FK$min_spacing_m, paste(sprintf("%s %d (%d)", names(FK$points_per_class), vapply(names(FK$points_per_class), function(k) sum(sp$class == k), 0L), unlist(FK$points_per_class)), collapse = ", ")),
  sprintf("Classes that cover little accessible land (%s) fall short of their targets, so their accuracy will be estimated from few points; observers' own building counts and wildland cover will still test the intermix class, which holds %.0f%% of WUI buildings.",
          paste(names(FK$points_per_class)[vapply(names(FK$points_per_class), function(k) sum(sp$class == k) < FK$points_per_class[[k]], TRUE)], collapse = ", "),
          100 * sum(ob$class_calibrated == "intermix") / max(1, sum(ob$in_wui)))),
  size = c(6.5, 6))

write_process(run, GT, "exposure_by_gewog")
write_process(run, data.frame(priority = PR_LAB, area_km2 = pk, buildings = bk), "priority_classes")
write_process(run, as.data.frame(table(class = sp$class, unit = sp$unit)) |> subset(Freq > 0), "field_points_by_class_unit")
write_json_pretty(list(wui_people = sum(GT$wui_people), people_thimphu = sum(pop), wui_buildings = sum(GT$wui_buildings), remote_share = rem,
                       road_km_in_wui = sum(GT$road_km_in_wui), priority = data.frame(priority = PR_LAB, area_km2 = pk, buildings = bk),
                       top_unit = GT$unit[1], gewog_table = GT, field_points = nrow(sp), field_by_class = as.list(table(sp$class))), tw("data/derived/results_exposure.json"))
build_report(run, intro = c(
  sprintf("Exposure in the calibrated wildland-urban interface of Thimphu: %s buildings and about %.0f people (WorldPop 2020) in WUI; %.1f km2 of WUI combines high fire susceptibility with recent fire within 1 km.",
          format(sum(GT$wui_buildings), big.mark = ","), sum(GT$wui_people), pk[1]),
  sprintf("Gewog priority order: %s. A blind field validation kit of %d points is in data/derived/field_kit/.", paste(GT$unit, collapse = ", "), nrow(sp))))
print(GT[, c("unit", "priority_rank", "wui_buildings", "wui_fire_exposed_buildings", "wui_high_susceptibility_buildings", "wui_people")])
