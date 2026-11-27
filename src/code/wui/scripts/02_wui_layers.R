# 02  WUI layers, baseline map, one-at-a-time sensitivity and source checks for Thimphu dzongkhag
# Raster adaptation of Radeloff et al. (2005) on a 50 m grid. For every cell, within a circular neighbourhood of
# radius R: building density (Open Buildings V3 centroids, confidence >= 0.70, per km2) and wildland vegetation
# cover (%). Large vegetated patches = connected cells with >= 75% vegetation and area >= A km2.
#   intermix  = density > D and vegetation >= V
#   interface = density > D, vegetation < V, within P m of a large vegetated patch
#   non-WUI   = vegetated (density <= D, vegetation >= V) / developed (density > D, far from patches) / other
# Three wildland-vegetation definitions are carried: forest-type-map forest + scrub (baseline), WorldCover tree +
# shrub, WorldCover tree + shrub + grass. All neighbourhood layers are saved in data/derived/layers/ for scripts 03-05.
# Run: Rscript thimphu_WUI/scripts/02_wui_layers.R   (after 01)
source(if (file.exists("thimphu_WUI/R/tw_common.R")) "thimphu_WUI/R/tw_common.R" else "R/tw_common.R")
source(tw("R/sci_figure.R")); suppressPackageStartupMessages({ library(patchwork) })
terraOptions(memfrac = 0.5, progress = 0)
# ============================================================
# CONFIGURATION
# ============================================================
SLUG <- "01-sensitivity"
TITLE <- "Wildland-urban interface of Thimphu: layers, baseline map and sensitivity"
G <- CFG$sensitivity_grid; B <- CFG$baseline; CONF <- CFG$buildings$confidence_min; PV <- CFG$patch_vegetation_share
LAY <- tw("data/derived/layers")
# ============================================================
# Reuse the existing output tree; overwrite generated files without recreating folders.
run <- sci_run(SLUG, TITLE, inputs = c(tw("data/inputs/x")))
dir.create(LAY, recursive = TRUE, showWarnings = FALSE)
g <- grid50(); zone <- values(g, mat = FALSE); inside <- zone %in% 2
gid <- rast(tw("data/inputs/gewog_50m.tif")); glev <- levels(gid)[[1]]
gewog_of_cell <- glev[[2]][match(values(gid, mat = FALSE), glev[[1]])]
ob_all <- st_read(tw("data/inputs/buildings.gpkg"), "open_buildings_v3", quiet = TRUE)
ag <- st_read(tw("data/inputs/buildings.gpkg"), "agency", quiet = TRUE)
ob <- ob_all[ob_all$confidence >= CONF, ]
cell_ob <- cellFromXY(g, st_coordinates(ob)); cell_ag <- cellFromXY(g, st_coordinates(ag))
count_r <- function(cell) { r <- rast(g); n <- tabulate(cell[!is.na(cell)], ncell(g)); values(r) <- n; mask(r, g) }
bcount <- count_r(cell_ob); acount <- count_r(cell_ag)

vs <- rast(tw("data/inputs/vegetation_shares_50m.tif")) / 100
VEG <- list(ftm = vs[["ftm_forest_scrub"]], wc_woody = vs[["wc_tree"]] + vs[["wc_shrub"]],
            wc_woody_grass = vs[["wc_tree"]] + vs[["wc_shrub"]] + vs[["wc_grass"]])
VEG <- lapply(VEG, function(v) mask(v, vs[["ftm_forest_scrub"]]))   # same Bhutan-only domain for all definitions

# ---- neighbourhood layers (saved for 03-05) ----------------------------------------------------------------------
dens <- list(); dens_ag <- list()
for (r in G$R) { w <- circle_w(g, r); a <- sum(w) * (RES / 1000)^2
  dens[[as.character(r)]] <- focal(bcount, w, fun = "sum", na.rm = TRUE) / a
  dens_ag[[as.character(r)]] <- focal(acount, w, fun = "sum", na.rm = TRUE) / a }
D_r <- rast(dens); names(D_r) <- paste0("r", G$R); writeRaster(D_r, file.path(LAY, "density_ob.tif"), overwrite = TRUE, gdal = "COMPRESS=DEFLATE")
DA_r <- rast(dens_ag); names(DA_r) <- paste0("r", G$R); writeRaster(DA_r, file.path(LAY, "density_agency.tif"), overwrite = TRUE, gdal = "COMPRESS=DEFLATE")
for (v in names(VEG)) {
  vp <- rast(lapply(G$R, function(r) 100 * focal(VEG[[v]], circle_w(g, r), fun = "mean", na.rm = TRUE))); names(vp) <- paste0("r", G$R)
  writeRaster(vp, file.path(LAY, sprintf("vegpct_%s.tif", v)), overwrite = TRUE, gdal = "COMPRESS=DEFLATE")
  pid <- patches(ifel(VEG[[v]] >= PV, 1, NA), directions = 8, zeroAsNA = TRUE)
  pa <- freq(pid); pa$km2 <- pa$count * (RES / 1000)^2
  pd <- rast(lapply(G$A, function(a) mask(distance(classify(pid, cbind(pa$value, ifelse(pa$km2 >= a, 1, NA)))), g)))
  names(pd) <- paste0("a", G$A)
  writeRaster(pd, file.path(LAY, sprintf("patchdist_%s.tif", v)), overwrite = TRUE, gdal = "COMPRESS=DEFLATE")
  writeRaster(VEG[[v]], file.path(LAY, sprintf("vegshare_%s.tif", v)), overwrite = TRUE, gdal = "COMPRESS=DEFLATE")
  message("layers: ", v)
}
writeRaster(bcount, file.path(LAY, "building_count_ob.tif"), overwrite = TRUE, gdal = "COMPRESS=DEFLATE")

# ---- classification helpers ------------------------------------------------------------------------------------------
vals <- function(r) values(r, mat = FALSE)[inside]
LV <- function(v, r) vals(rast(file.path(LAY, sprintf("vegpct_%s.tif", v)))[[paste0("r", r)]])
LP <- function(v, a) vals(rast(file.path(LAY, sprintf("patchdist_%s.tif", v)))[[paste0("a", a)]])
LD <- function(r, agency = FALSE) vals((if (agency) DA_r else D_r)[[paste0("r", r)]])
BC <- vals(bcount); AC <- vals(acount); GW <- gewog_of_cell[inside]
cls <- function(x, agency = FALSE) classify_wui(LD(x$R, agency), LV(x$veg, x$R), LP(x$veg, x$A), x$D, x$V, x$P)
summ <- function(cl, bc, extra) data.frame(extra, class = CLASSES,
  area_km2 = vapply(1:5, function(k) sum(cl == k, na.rm = TRUE), 0) * (RES / 1000)^2,
  buildings = vapply(1:5, function(k) sum(bc[cl %in% k]), 0), row.names = NULL)
base <- B[c("D", "V", "P", "R", "A", "veg")]
base_cl <- cls(base)

# ---- one-at-a-time sensitivity around the baseline ---------------------------------------------------------------------
oat <- do.call(rbind, lapply(c("D", "V", "P", "R", "A", "veg"), function(par) do.call(rbind, lapply(G[[par]], function(val) {
  x <- base; x[[par]] <- val; cl <- cls(x); w <- cl %in% 1:2
  data.frame(parameter = par, value = as.character(val), baseline = identical(as.character(val), as.character(base[[par]])),
             wui_km2 = sum(w) * (RES / 1000)^2, intermix_km2 = sum(cl == 1, na.rm = TRUE) * (RES / 1000)^2,
             wui_buildings = sum(BC[w]), building_share = sum(BC[w]) / sum(BC)) }))))

# ---- source checks: building source and vegetation definition ----------------------------------------------------------------
src <- rbind(summ(base_cl, BC, data.frame(check = "Buildings", source = "Open Buildings V3 (2023)")),
             summ(cls(base, agency = TRUE), AC, data.frame(check = "Buildings", source = "Agency layer (2012-2014)")),
             do.call(rbind, lapply(names(VEG), function(v) { x <- base; x$veg <- v
               summ(cls(x), BC, data.frame(check = "Vegetation", source = VEG_LABEL[[v]])) })))
src <- do.call(rbind, lapply(split(src, src$source), function(d) { d$area_share <- d$area_km2 / sum(d$area_km2); d$building_share <- d$buildings / sum(d$buildings); d }))
agree_v <- do.call(rbind, lapply(setdiff(names(VEG), "ftm"), function(v) { x <- base; x$veg <- v; cv <- cls(x); ok <- !is.na(cv) & !is.na(base_cl)
  data.frame(comparison = paste("Forest-type map vs", VEG_LABEL[[v]]), wui_agreement = mean((cv[ok] %in% 1:2) == (base_cl[ok] %in% 1:2)),
             kappa_5class = md_kappa(base_cl[ok], cv[ok], 1:5)[["kappa"]]) }))
conf_tab <- data.frame(confidence_min = CFG$buildings$confidence_test,
                       buildings_in_thimphu = vapply(CFG$buildings$confidence_test, function(t) { cc <- cellFromXY(g, st_coordinates(ob_all[ob_all$confidence >= t, ])); sum(zone[cc] %in% 2) }, 0))
conf_tab <- rbind(conf_tab, data.frame(confidence_min = NA, buildings_in_thimphu = sum(zone[cell_ag] %in% 2, na.rm = TRUE)))
conf_tab$source <- c(rep("Open Buildings V3", length(CFG$buildings$confidence_test)), "Agency layer")
by_gewog <- do.call(rbind, lapply(sort(unique(GW[!is.na(GW)])), function(z) { s <- GW %in% z
  cbind(gewog = z, summ(base_cl[s], BC[s], data.frame(criteria = "baseline (US)")))[, c("gewog", "class", "area_km2", "buildings")] }))

# ---- outputs: rasters ---------------------------------------------------------------------------------------------------------
fill <- function(v) { r <- rast(g); x <- rep(NA_real_, ncell(g)); x[inside] <- v; values(r) <- x; r }
base_r <- fill(base_cl); levels(base_r) <- data.frame(value = 1:5, class = CLASSES)
writeRaster(base_r, tw("data/derived/wui_class_baseline_50m.tif"), overwrite = TRUE, datatype = "INT1U", gdal = "COMPRESS=DEFLATE")

# ============================================================
# DATA HEALTH
# ============================================================
data_health(run, st_drop_geometry(ob_all)[, c("confidence", "area_m2")], "Open Buildings V3 centroids in the Thimphu buffer (all confidences)")
smp <- sample(which(!is.na(base_cl)), min(20000, sum(!is.na(base_cl))))
data_health(run, data.frame(density_r500 = LD(500)[smp], veg_ftm_r500 = LV("ftm", 500)[smp], veg_wcg_r500 = LV("wc_woody_grass", 500)[smp],
                            dist_patch_5km2 = LP("ftm", 5)[smp], buildings_in_cell = BC[smp]), "Random sample of 50 m cells inside Thimphu (baseline layers)")
data_health(run, oat[, c("parameter", "wui_km2", "wui_buildings", "building_share")], "One-at-a-time sensitivity")
nthim <- sum(BC)
write_health(run, notes = c(
  sprintf("Open Buildings V3: %s footprints in the buffer; %s inside Thimphu at confidence >= %.2f. Confidence thresholds are not validated for Bhutan.",
          format(nrow(ob_all), big.mark = ","), format(nthim, big.mark = ","), CONF),
  sprintf("Agency building layer: %s centroids inside Thimphu; edit years mostly %s, so it predates recent growth.", format(sum(AC), big.mark = ","),
          paste(names(sort(table(ag$edit_year), decreasing = TRUE))[1:2], collapse = " and ")),
  "Wildland vegetation is masked to Bhutan for every definition (the forest-type map has no data outside Bhutan).",
  "Radeloff et al. (2005) used census blocks and housing units; this raster neighbourhood adaptation uses building footprints, so areas are not comparable with US or global WUI products."))

# ============================================================
# FIGURES
# ============================================================
dz <- study_dz(); gw <- study_gewogs()
mapdf <- function(r) { d <- as.data.frame(r, xy = TRUE, na.rm = TRUE); names(d)[3] <- "value"; d }
# Fig 1 building density
dd <- mapdf(mask(D_r[["r500"]], vect(dz))); dd <- dd[dd$value > 0, ]
p1 <- ggplot() + geom_raster(data = dd, aes(x, y, fill = value)) +
  scale_fill_viridis_c(trans = "log10", option = "magma", direction = -1, name = "Buildings per km2\n(500 m radius)", labels = scales::label_number(drop0trailing = TRUE)) +
  geom_sf(data = gw, fill = NA, colour = "#888888", linewidth = 0.25) + geom_sf(data = dz, fill = NA, colour = "black", linewidth = 0.5) +
  geom_sf_text(data = gw, aes(label = gewog), family = SCI$font, size = 2.4, colour = "#333333") +
  ggspatial::annotation_scale(location = "bl", text_family = SCI$font, height = unit(0.15, "cm")) + theme_sci_map() + theme(legend.position = "right")
q99 <- quantile(LD(500)[LD(500) > 0], 0.99); share_above <- sum(BC[LD(500) > B$D]) / nthim
save_fig(run, p1, 1, "building_density", data.frame(statistic = c("median occupied", "p99", "share of buildings above D"), value = c(median(LD(500)[LD(500) > 0]), q99, share_above)), c(
  sprintf("Building density within a 500 m radius in Thimphu dzongkhag (Open Buildings V3, confidence >= %.2f, n = %s).", CONF, format(nthim, big.mark = ",")),
  "Moving-window count of footprint centroids per km2 on a 50 m grid, log colour scale, cells with no building in the window left blank; grey lines are gewogs.",
  sprintf("%.1f%% of buildings stand in neighbourhoods above the US threshold of %.2f/km2, so the density rule alone excludes almost no settlement and the vegetation and proximity rules decide the WUI extent.", 100 * share_above, B$D)),
  size = c(6.5, 6))

# Fig 2 baseline WUI map
bd <- mapdf(mask(base_r, vect(dz))); bd$value <- factor(bd$value, CLASSES)
bshare <- sum(BC[base_cl %in% 1:2]) / nthim; barea <- sum(base_cl %in% 1:2) * (RES / 1000)^2
p2 <- ggplot() + geom_raster(data = bd, aes(x, y, fill = value)) + scale_fill_manual(values = WUI_COLS, name = NULL, drop = FALSE) +
  geom_sf(data = gw, fill = NA, colour = "#666666", linewidth = 0.25) + geom_sf(data = dz, fill = NA, colour = "black", linewidth = 0.5) +
  ggspatial::annotation_scale(location = "bl", text_family = SCI$font, height = unit(0.15, "cm")) + theme_sci_map() + theme(legend.position = "right")
save_fig(run, p2, 2, "wui_baseline_map", src[src$source == "Open Buildings V3 (2023)", ], c(
  "Wildland-urban interface of Thimphu dzongkhag under the US baseline criteria (Radeloff et al. 2005, raster adaptation).",
  sprintf("Density > %.2f buildings/km2, vegetation >= %d%% (forest-type map forest + scrub), within %d m of a >= %d km2 patch, %d m neighbourhood, 50 m grid.", B$D, B$V, B$P, B$A, B$R),
  sprintf("WUI covers %.0f km2 (%.0f%% of the dzongkhag) yet holds %.0f%% of its buildings, so the US criteria flag nearly every settlement and cannot by themselves separate high- from low-exposure communities; script 03 calibrates them against local fire evidence.",
          barea, 100 * barea / (sum(inside) * (RES / 1000)^2), 100 * bshare)),
  size = c(6.5, 6))

# Fig 3 one-at-a-time sensitivity
oat$parameter_label <- factor(c(D = "Density D (/km2)", V = "Vegetation V (%)", P = "Proximity P (m)", R = "Radius R (m)", A = "Patch A (km2)", veg = "Vegetation source")[oat$parameter],
                              c("Density D (/km2)", "Vegetation V (%)", "Proximity P (m)", "Radius R (m)", "Patch A (km2)", "Vegetation source"))
oat$value_label <- ifelse(oat$parameter == "veg", c(ftm = "FTM", wc_woody = "WC woody", wc_woody_grass = "WC +grass")[oat$value], oat$value)
oat$value_label <- factor(oat$value_label, unique(oat$value_label[order(oat$parameter, suppressWarnings(as.numeric(oat$value)))]))
p3 <- ggplot(oat, aes(value_label, 100 * building_share, group = 1)) + geom_line(linewidth = 0.4) +
  geom_point(aes(shape = baseline), size = 2) + scale_shape_manual(values = c(`TRUE` = 16, `FALSE` = 1), guide = "none") +
  geom_text(aes(label = sprintf("%.0f", wui_km2)), vjust = -0.9, size = 2.4, family = SCI$font) +
  facet_wrap(~ parameter_label, scales = "free_x", ncol = 3) + scale_y_continuous(limits = c(0, 108)) +
  labs(x = NULL, y = "Buildings in WUI (% of Thimphu)") + theme_sci() + theme(axis.text.x = element_text(angle = 30, hjust = 1, size = 7))
rng <- tapply(oat$building_share, oat$parameter, function(x) diff(range(x)))
save_fig(run, p3, 3, "sensitivity_one_at_a_time", oat, c(
  "Share of Thimphu buildings classified as WUI when one criterion is varied and the others stay at the US baseline.",
  "Filled points are baseline values; labels give total WUI area (km2); vegetation sources: forest-type map (FTM), WorldCover tree + shrub, WorldCover tree + shrub + grass.",
  sprintf("Proximity P moves the building share most (range %.0f percentage points), followed by %s (%.1f percentage points), so the proximity distance is the choice that most needs local evidence.",
          100 * rng[["P"]], names(sort(rng[names(rng) != "P"], decreasing = TRUE))[1], 100 * max(rng[names(rng) != "P"]))),
  size = c(7.2, 5))

# Fig 4 source checks
src$class <- factor(src$class, rev(CLASSES)); src$source <- factor(src$source, unique(src$source))
p4 <- ggplot(src, aes(source, area_km2, fill = class)) + geom_col(colour = "black", linewidth = 0.2, width = 0.65) +
  scale_fill_manual(values = WUI_COLS, name = NULL, breaks = CLASSES) + coord_flip() +
  facet_grid(check ~ ., scales = "free_y", space = "free_y") + labs(x = NULL, y = "Area inside Thimphu (km2)") + theme_sci() + theme(legend.position = "bottom")
wb <- function(s) sum(src$buildings[src$source == s & src$class %in% c("intermix", "interface")])
save_fig(run, p4, 4, "source_checks", src, c(
  "WUI class area in Thimphu under the baseline criteria with two building sources and three wildland-vegetation definitions.",
  sprintf("Each source defines its own densities or vegetation shares, all other rules fixed at baseline; WUI versus non-WUI cell agreement with the forest-type-map baseline: %s.",
          paste(sprintf("%.0f%% (%s)", 100 * agree_v$wui_agreement, sub("Forest-type map vs ", "", agree_v$comparison)), collapse = ", ")),
  sprintf("Open Buildings puts %s buildings in WUI against %s in the agency layer, so the building source changes exposure counts more than the vegetation definition, which mainly moves cells between intermix and interface.",
          format(wb("Open Buildings V3 (2023)"), big.mark = ","), format(wb("Agency layer (2012-2014)"), big.mark = ","))),
  size = c(7.2, 4.4))

write_process(run, conf_tab, "building_counts_by_source_and_confidence")
write_process(run, src, "source_checks_class_area_buildings")
write_process(run, agree_v, "vegetation_definition_agreement")
write_process(run, oat, "sensitivity_one_at_a_time")
write_process(run, by_gewog, "baseline_by_gewog")
write_json_pretty(list(buildings_thimphu = nthim, baseline_wui_km2 = barea, baseline_building_share = bshare, share_above_D = share_above,
                       agency_buildings_thimphu = sum(AC), oat_range_building_share = as.list(rng), veg_agreement = agree_v,
                       wui_buildings_ob = wb("Open Buildings V3 (2023)"), wui_buildings_agency = wb("Agency layer (2012-2014)")),
                  tw("data/derived/results_layers.json"))
build_report(run, intro = c(
  sprintf("Wildland-urban interface layers for Thimphu dzongkhag (%s buildings, 50 m grid). Under the US baseline criteria WUI covers %.0f km2 and %.0f%% of buildings.", format(nthim, big.mark = ","), barea, 100 * bshare),
  "Neighbourhood layers for all tested criteria are saved for the fire-based calibration (output 02), growth analysis (03) and exposure assessment (04)."))
