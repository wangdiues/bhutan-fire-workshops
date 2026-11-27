# 16  Maps, tables, data-health report and report.pdf for the fire-line and prescribed-burn analysis (after 15)
# Criteria v3 (docs/Criteria for firelines and prescribed burning.docx); segmented fire lines only (no continuous option).
# Run: Rscript thimphu_WUI/scripts/16_fire_mgmt_figures.R
source(if (file.exists("thimphu_WUI/R/tw_common.R")) "thimphu_WUI/R/tw_common.R" else "R/tw_common.R")
source(tw("R/sci_figure.R")); suppressPackageStartupMessages({ library(patchwork) })
terraOptions(memfrac = 0.5, progress = 0)
# ============================================================
# CONFIGURATION
# ============================================================
FM <- CFG$fire_management; FL <- FM$fire_lines; RX <- FM$rx_burn
SLUG <- FM$slug
TITLE <- "Fire-line siting and prescribed-burn site selection for the Thimphu wildland-urban interface"
IN <- tw(FM$inputs_dir); OUTD <- tw(FM$outputs_dir)
FG <- FM$figures; FCOL <- FG$colours
SCI$dpi <- FG$dpi                                   # map resolution for this pipeline (settings: fire_management.figures)
# ============================================================
run <- sci_run(SLUG, TITLE, inputs = c(file.path(OUTD, "x"), file.path(IN, "x")))
gp <- file.path(OUTD, "fire_management_thimphu.gpkg")
LS <- st_read(gp, "fire_lines_segmented", quiet = TRUE); RXS <- st_read(gp, "rx_burn_sites", quiet = TRUE)
PK <- st_read(gp, "candidate_line_pieces", quiet = TRUE); SC <- st_read(gp, "rx_suitability_classes", quiet = TRUE)
S <- readRDS(file.path(OUTD, "run_state.rds"))
funnel <- S$funnel; funnel_fl <- S$funnel_fl; SENS_FL <- S$SENS_FL; SENS_RX <- S$SENS_RX
dz <- study_dz(); gw <- study_gewogs()
L <- function(n) st_read(file.path(IN, "layers.gpkg"), n, quiet = TRUE)
nogo <- L("no_go_areas"); streams <- L("streams")
dem <- rast(file.path(IN, "dem_50m.tif"))
hs <- shade(terrain(dem, "slope", unit = "radians"), terrain(dem, "aspect", unit = "radians"), 40, 315)
ob <- st_read(tw("data/derived/wui_thimphu.gpkg"), "buildings", quiet = TRUE)
nc <- L("buildings_ncrp")
roads <- st_read(tw("data/inputs/roads_osm.gpkg"), quiet = TRUE)
COMP <- c("exposure", "fuel", "fire", "susceptibility", "topography")
EXG <- file.path(OUTD, "exclusion_layers.gpkg"); EXL <- lapply(setNames(st_layers(EXG)$name, st_layers(EXG)$name), function(n) st_read(EXG, n, quiet = TRUE))

# ============================================================
# DATA HEALTH
# ============================================================
pk <- st_drop_geometry(PK)
data_health(run, pk[, c("score", paste0("c_", COMP), "wui_bld", "bld_dist_min", "fire_n", "slope_mean", "elev", "veg_share", "feasible")], "Candidate 100 m fire-line pieces")
data_health(run, st_drop_geometry(LS)[, c("built_length_m", "cleared_ha", "slope_mean_deg", "wui_buildings_200m", "nearest_building_m", "fuel_index", "fire_evidence_1km", "score_mean")], "Selected fire-line segments")
data_health(run, st_drop_geometry(RXS)[, c("area_ha", "elev_mean_m", "slope_mean_deg", "grass_pct", "tree_pct", "canopy_cover_pct", "fuel_index", "nearest_building_m", "wui_buildings_500m", "holding_edge_share", "score")], "Selected prescribed-burn sites")
write_health(run, notes = c(
  sprintf("Candidate edge: %d pieces (%.0f km) along the developed footprint (Open Buildings V3 + %s NCRP footprints + registered private land); %d pieces (%.0f km) pass all %d fire-line exclusions.",
          nrow(pk), sum(pk$len_m) / 1000, format(nrow(nc), big.mark = ","), sum(pk$feasible), sum(pk$len_m[pk$feasible]) / 1000, nrow(funnel_fl) - 1),
  sprintf("No-go areas supplied by DoFPS (%s) are excluded for fire lines and with a %d m margin for burning.", paste(nogo$name, collapse = "; "), FM$no_go_areas$rx_buffer_m),
  "WUI class is the calibrated legacy map; exposure counts are screening values.",
  "Fuel descriptors are NFI 2021-2022 random-forest predictions at 100 m, resampled to 50 m; 50 m cells cannot locate a line to better than about 25 m.",
  "Canopy cover (NFI model) and tree cover (WorldCover) disagree on the selected burn sites; the field densiometer reading decides (field validation protocol).",
  "Building distances use Open Buildings points and NCRP footprint polygons; setbacks are checked on actual geometry.",
  "Cultural sites and landslide susceptibility are not available as spatial data and are checked in the field.",
  "Scores are relative ranks within Thimphu, not probabilities. Field verification of every line and site is required before work."))

# ============================================================
# helpers: basemap (satellite / OSM / topo tiles cached locally, or hillshade) and map symbols
# ============================================================
if (!requireNamespace("ggnewscale", quietly = TRUE)) stop("Package ggnewscale is required for the maps.")
IMG <- FG$basemap != "hillshade"                       # imagery-style basemap: light symbols, no building dots
BMN <- FG$attribution[[FG$basemap]]
hs_df <- function(bb) { r <- crop(hs, ext(bb)); d <- as.data.frame(r, xy = TRUE, na.rm = TRUE); names(d)[3] <- "hs"; d }
zoom_for <- function(bb, width_in) {                  # web-map zoom giving ~tile_px_per_in pixels per inch of figure
  res <- (bb["xmax"] - bb["xmin"]) / (width_in * FG$tile_px_per_in)
  z <- ceiling(log2(156543.03 * cos(27.45 * pi / 180) / res)); unname(max(FG$min_zoom, min(FG$max_zoom, z))) }
dir.create(tw(FG$tile_cache), recursive = TRUE, showWarnings = FALSE)
bm_layers <- function(bb, width_in, kind = FG$basemap) {
  if (kind != "hillshade") {
    t <- tryCatch(maptiles::get_tiles(st_as_sfc(bb), provider = FG$providers[[kind]], zoom = zoom_for(bb, width_in), crop = TRUE,
                                      cachedir = tw(FG$tile_cache), forceDownload = FALSE),
                  error = function(e) { message("  basemap tiles unavailable (", conditionMessage(e), "); hillshade used"); NULL })
    if (!is.null(t)) return(list(tidyterra::geom_spatraster_rgb(data = t, maxcell = ncell(t)), ggnewscale::new_scale_fill()))
  }
  list(geom_raster(data = hs_df(bb), aes(x, y, fill = hs), show.legend = FALSE),
       scale_fill_gradient(low = "#9a9a9a", high = "#ffffff", guide = "none"), ggnewscale::new_scale_fill())
}
base_map <- function(bb, width_in, bsize = 0.25, balpha = 1) {
  b <- st_as_sfc(bb); rdx <- suppressWarnings(st_intersection(roads, b)); stx <- suppressWarnings(st_intersection(streams, b))
  ngx <- suppressWarnings(st_intersection(nogo, b))
  rcol <- if (IMG) FCOL$road else "#333333"
  ggplot() + bm_layers(bb, width_in) +
    geom_sf(data = stx, aes(colour = "Stream / river"), linewidth = 0.3, key_glyph = "path") +
    geom_sf(data = rdx, aes(colour = "Road / track / footpath"), linewidth = 0.22, alpha = if (IMG) 0.55 else 1, key_glyph = "path") +
    { if (!IMG) geom_sf(data = ob[lengths(st_intersects(ob, b)) > 0, ], aes(colour = "Building (Open Buildings)"), size = bsize, shape = 16, alpha = balpha) } +
    scale_colour_manual(values = c(`Stream / river` = FCOL$stream, `Road / track / footpath` = rcol, `Building (Open Buildings)` = "#555555"), name = NULL,
                        guide = guide_legend(order = 4, override.aes = list(linewidth = 0.8, alpha = 1))) + ggnewscale::new_scale_colour() +
    geom_sf(data = ngx, aes(fill = "No-go area (plantation / reserved site)"), colour = FCOL$no_go, alpha = 0.3, linewidth = 0.7) +
    scale_fill_manual(values = c(`No-go area (plantation / reserved site)` = FCOL$no_go), name = NULL, guide = guide_legend(order = 3, override.aes = list(alpha = 0.4))) +
    ggnewscale::new_scale_fill() + theme_sci_map()
}
fit <- function(bb) coord_sf(xlim = c(bb["xmin"], bb["xmax"]), ylim = c(bb["ymin"], bb["ymax"]), expand = FALSE, datum = NA)
pad_bb <- function(x, pad, min_half = 0) { b <- st_bbox(x); cx <- (b["xmin"] + b["xmax"]) / 2; cy <- (b["ymin"] + b["ymax"]) / 2
  h <- max((b["xmax"] - b["xmin"]) / 2, (b["ymax"] - b["ymin"]) / 2, min_half) + pad
  st_bbox(c(xmin = unname(cx - h), ymin = unname(cy - h), xmax = unname(cx + h), ymax = unname(cy + h)), crs = st_crs(x)) }
scale_bar <- function(loc = "bl", cex = 0.7, img = IMG) ggspatial::annotation_scale(location = loc, text_family = SCI$font, height = unit(0.12, "cm"), text_cex = cex,
  text_col = if (img) "white" else "black", text_face = if (img) "bold" else "plain", line_col = if (img) "white" else "black", bar_cols = c("black", "white"))
north <- function() ggspatial::annotation_north_arrow(location = "tr", height = unit(0.9, "cm"), width = unit(0.7, "cm"),
  style = ggspatial::north_arrow_fancy_orienteering(text_family = SCI$font, text_col = if (IMG) "white" else "black", line_col = if (IMG) "white" else "black",
                                                    fill = c(if (IMG) "white" else "black", if (IMG) "black" else "white")))
leg_theme <- theme(legend.position = "bottom", legend.box = "vertical", legend.direction = "horizontal", legend.text = element_text(size = 8),
                   legend.key = element_rect(fill = if (IMG) "#7f8c7a" else "white", colour = NA), legend.key.width = unit(0.9, "cm"),
                   legend.spacing.y = unit(0.05, "cm"), legend.margin = margin(1, 1, 1, 1))
pts <- function(x) { p <- suppressWarnings(st_point_on_surface(x)); cbind(st_drop_geometry(p), st_coordinates(p)) }
# fire lines: red with white casing; burn sites: yellow with black edge; markers make both visible at dzongkhag scale
fl_layers <- function(x, lw = 1.5) list(geom_sf(data = x, colour = "white", linewidth = lw + 1.2, lineend = "round"),
                                         geom_sf(data = x, colour = FCOL$fire_line, linewidth = lw, lineend = "round"))
rx_layers <- function(x, alpha = 0.55) list(geom_sf(data = x, fill = NA, colour = "white", linewidth = 1.4),
                                             geom_sf(data = x, fill = FCOL$rx_fill, colour = FCOL$rx_edge, alpha = alpha, linewidth = 0.6))
SHP_FL <- sprintf("Fire-line segment (%s to %s)", LS$segment[1], LS$segment[nrow(LS)])
SHP_RX <- sprintf("Prescribed-burn site (%s to %s)", RXS$site[1], RXS$site[nrow(RXS)])
marker_layers <- function(size = 3.4) {
  rp <- pts(RXS)
  list(geom_point(data = rp, aes(X, Y, shape = SHP_RX), fill = FCOL$rx_fill, colour = "black", size = size, stroke = 0.9),
       scale_shape_manual(values = setNames(21, SHP_RX), name = NULL),
       guides(shape = guide_legend(order = 1, override.aes = list(fill = FCOL$rx_fill, colour = "black", size = 3.5))))
}
# selected fire-line segments as bold red lines with a white casing, shown in the legend as a line
fl_legend_layers <- function(x, lw = 2) list(
  ggnewscale::new_scale_colour(),
  geom_sf(data = x, colour = "white", linewidth = lw + 0.9, lineend = "round"),
  geom_sf(data = x, aes(colour = SHP_FL), linewidth = lw, lineend = "round", key_glyph = "path"),
  scale_colour_manual(values = setNames(FCOL$fire_line, SHP_FL), name = NULL, guide = guide_legend(order = 1, override.aes = list(linewidth = 1.6))))
labels_layers <- function() {
  lp <- pts(LS); rp <- pts(RXS)
  d <- rbind(data.frame(X = lp$X, Y = lp$Y, label = lp$segment, fill = "white", col = FCOL$fire_line),
             data.frame(X = rp$X, Y = rp$Y, label = rp$site, fill = FCOL$rx_fill, col = "black"))
  list(ggrepel::geom_label_repel(data = d, aes(X, Y, label = label), family = SCI$font, fontface = "bold", size = 2.6, fill = d$fill, colour = d$col,
                                 label.size = 0.3, label.padding = 0.13, min.segment.length = 0, segment.colour = "white", segment.size = 0.5,
                                 box.padding = 0.7, point.padding = 0.4, force = 3, max.overlaps = Inf, seed = 1))
}

# ============================================================
# FIGURE 1: overview
# ============================================================
bb1 <- pad_bb(st_sf(geometry = c(st_geometry(LS), st_geometry(RXS), st_geometry(nogo))), 1200)
cand <- PK[PK$feasible, ]; cand <- cand[lengths(st_intersects(cand, st_as_sfc(bb1))) > 0, ]
p1 <- base_map(bb1, 7.2, bsize = 0.08, balpha = 0.35) + geom_sf(data = gw, aes(colour = "Gewog boundary"), fill = NA, linewidth = 0.4, linetype = "dashed", key_glyph = "path") +
  geom_sf(data = cand, aes(colour = "Feasible fire-line edge (not selected)"), linewidth = 0.45, key_glyph = "path") +
  scale_colour_manual(values = c(`Feasible fire-line edge (not selected)` = FCOL$candidate, `Gewog boundary` = if (IMG) "white" else "#444444"), name = NULL,
                      guide = guide_legend(order = 2, override.aes = list(linewidth = 1, linetype = c("solid", "dashed")))) +
  rx_layers(RXS) + fl_legend_layers(LS, 1.1) + marker_layers() + labels_layers() +
  scale_bar() + north() + fit(bb1) + leg_theme
tl <- st_drop_geometry(LS)
save_fig(run, p1, 1, "overview_map", tl[, c("segment", "gewog", "nearest_village", "built_length_m", "cleared_ha", "wui_buildings_200m", "score_mean")], c(
  sprintf("Proposed fire lines (%d segments, %s m) and seven prescribed-burn sites (%.0f ha) at the wildland-urban interface of Thimphu.", nrow(LS), format(sum(LS$built_length_m), big.mark = ","), sum(RXS$area_ha)),
  sprintf("Bold red lines (white outline) = fire-line segments chosen by exact dynamic programming; yellow circles and yellow polygons = burn sites chosen by integer programming; pink = %.0f km of candidate edge passing all fire-line exclusions; magenta = DoFPS no-go areas; %s.",
          sum(pk$len_m[pk$feasible]) / 1000, BMN),
  sprintf("Fire lines protect settlement edges in %s and burn sites lie in %s; the nearest selection is %.1f km from a no-go area.",
          paste(sort(unique(LS$gewog)), collapse = ", "), paste(sort(unique(RXS$gewog)), collapse = ", "),
          min(as.numeric(st_distance(c(st_geometry(LS), st_geometry(RXS)), nogo))) / 1000)),
  size = c(7.2, 8.2))

# ============================================================
# FIGURE 2: fire-line segments (colour = width)
# ============================================================
pk_sel <- PK[PK$selected_segmented & PK$feasible, ]; ws <- sort(unique(pk_sel$width_m))
WCOL <- setNames(colorRampPalette(c(FCOL$fire_line, "#FF9F1C"))(length(ws)), paste(ws, "m"))
pk_sel$width <- factor(paste(pk_sel$width_m, "m"), names(WCOL))
seg_of <- st_join(pk_sel, LS[, "segment"], join = st_is_within_distance, dist = 1, left = TRUE); seg_of <- seg_of[!duplicated(seg_of$pid), ]
panels <- lapply(seq_len(nrow(LS)), function(i) { s <- LS[i, ]; bb <- pad_bb(s, 250, 350); pp <- seg_of[seg_of$segment %in% s$segment, ]
  base_map(bb, 2.4) + geom_sf(data = pp, colour = "white", linewidth = 2.8, lineend = "round") +
    geom_sf(data = pp, aes(colour = width), linewidth = 1.7, lineend = "round", show.legend = "line") + scale_colour_manual(values = WCOL, name = "Cleared width", drop = FALSE) +
    annotate("label", x = bb["xmin"] + 30, y = bb["ymax"] - 30, hjust = 0, vjust = 1, family = SCI$font, size = 2.5, linewidth = 0.15,
             label = sprintf("%s  %s, %s\n%d m | %d WUI bldgs | %d m to house", s$segment, s$nearest_village, s$gewog, s$built_length_m, s$wui_buildings_200m, s$nearest_building_m)) +
    scale_bar("br", 0.6) + fit(bb) })
p2 <- wrap_plots(panels, ncol = 3, guides = "collect") & leg_theme
save_fig(run, p2, 2, "fire_line_segments", st_drop_geometry(LS)[, c("segment", "gewog", "nearest_village", "built_length_m", "width_m_mix", "cleared_ha", "slope_mean_deg", "wui_buildings_200m", "nearest_building_m", "anchored_start", "anchored_end")], c(
  sprintf("The %d proposed fire-line segments, coloured by recommended cleared width.", nrow(LS)),
  sprintf("Width rule: %s; each segment is %d-%d m long, at least %d m from the next, %d-%d m from the nearest building and anchored at both ends on a road, footpath or stream within %d m; blue = streams, white = roads, magenta = no-go areas; %s.",
          FL$width_rule, FL$segmented$min_m, FL$segmented$max_m, FL$segmented$min_gap_m, FL$building_distance_m[1], FL$building_distance_m[2], FL$anchor_m, BMN),
  sprintf("%d of %d segments are anchored at both ends; clearing all of them removes about %.1f ha of vegetation along %s m of line.",
          sum(LS$anchored_start & LS$anchored_end), nrow(LS), sum(LS$cleared_ha), format(sum(LS$built_length_m), big.mark = ","))),
  size = c(7.2, 7.8))

# ============================================================
# FIGURE 3: prescribed-burn sites
# ============================================================
rpan <- lapply(seq_len(nrow(RXS)), function(i) { s <- RXS[i, ]; bb <- pad_bb(s, 300, 150)
  base_map(bb, 1.8) + rx_layers(s, 0.45) + fl_layers(LS, 1.2) +
    annotate("label", x = bb["xmin"] + 25, y = bb["ymax"] - 25, hjust = 0, vjust = 1, family = SCI$font, size = 2.4, linewidth = 0.15,
             label = sprintf("%s  %s, %s\n%.0f ha | %d m | %.0f deg %s", s$site, s$nearest_village, s$gewog, s$area_ha, s$elev_mean_m, s$slope_mean_deg, s$aspect)) +
    scale_bar("br", 0.6) + fit(bb) })
p3 <- wrap_plots(rpan, ncol = 4, guides = "collect") & leg_theme
save_fig(run, p3, 3, "rx_burn_sites", st_drop_geometry(RXS)[, c("site", "gewog", "nearest_village", "area_ha", "elev_mean_m", "slope_mean_deg", "aspect", "forest_type", "grass_pct", "tree_pct", "canopy_cover_pct", "fuel_index", "nearest_building_m", "holding_edge_share")], c(
  sprintf("The seven prescribed-burn sites (%.0f ha in total) selected for fuel reduction and subsequent planting.", sum(RXS$area_ha)),
  sprintf("Compact 2-6 ha units of 50 m cells passing all %d exclusion rules (open shrub/grass or open blue pine, fuel index >= %.2f, %d-%d m, slope <= %d deg, >= %d m from buildings, 0.1-0.75 km from WUI houses, >= %d m from no-go areas); yellow = site, red = fire line, blue = streams, white = roads; %s.",
          nrow(funnel) - 1, RX$min_fuel_index, RX$elev_m[1], RX$elev_m[2], RX$max_slope_deg, RX$min_building_m, FM$no_go_areas$rx_buffer_m, BMN),
  sprintf("Sites are %d-%d m from the nearest building with fuel index %.2f-%.2f; %d sites have no road, path or stream on their boundary and need cut control lines before burning.",
          min(RXS$nearest_building_m), max(RXS$nearest_building_m), min(RXS$fuel_index), max(RXS$fuel_index), sum(RXS$holding_edge_share == 0))),
  size = c(7.2, 4.8))

# ============================================================
# FIGURE 4: prescribed-burn suitability (criteria output 2)
# ============================================================
SC$class <- factor(SC$class, c("Low", "Moderate", "High"))
bb4 <- pad_bb(st_sf(geometry = c(st_geometry(SC), st_geometry(RXS))), 800)
p4 <- base_map(bb4, 7.2, bsize = 0.05, balpha = 0.3) + geom_sf(data = gw, aes(colour = "Gewog boundary"), fill = NA, linewidth = 0.35, linetype = "dashed", key_glyph = "path") +
  geom_sf(data = SC, aes(fill = class), colour = NA, alpha = 0.9) + scale_fill_manual(values = c(Low = "#fee391", Moderate = "#fe9929", High = "#cc4c02"), name = "Burning suitability") +
  geom_sf(data = RXS, aes(colour = "Selected burn-site boundary"), fill = NA, linewidth = 0.9, key_glyph = "path") +
  scale_colour_manual(values = c(`Gewog boundary` = if (IMG) "white" else "#444444", `Selected burn-site boundary` = "#00FFFF"), name = NULL,
                      guide = guide_legend(order = 2, override.aes = list(linewidth = 1, linetype = c("dashed", "solid")))) +
  fl_legend_layers(LS, 1.0) + marker_layers(2.8) + labels_layers() +
  scale_bar() + north() + fit(bb4) + leg_theme + guides(fill = guide_legend(order = 2))
save_fig(run, p4, 4, "rx_suitability", st_drop_geometry(SC)[, c("class", "score_range", "area_ha")], c(
  "Suitability of land for prescribed burning in Thimphu after all mandatory exclusions.",
  sprintf("Only cells passing every exclusion are shown, classed into terciles of the weighted score (fuel %.2f, exposure %.2f, susceptibility %.2f, fire history %.2f, access %.2f); cyan outlines and yellow circles = selected burn sites, bold red lines = fire lines; %s.",
          RX$weights$fuel, RX$weights$exposure, RX$weights$susceptibility, RX$weights$fire, RX$weights$access, BMN),
  sprintf("%.0f ha is eligible, %.0f ha of it in the high class; the selected sites cover %.0f ha and are mostly high or moderate.",
          sum(SC$area_ha), sum(SC$area_ha[SC$class == "High"]), sum(RXS$area_ha))),
  size = c(7.2, 7.8))

# ============================================================
# FIGURE 5: exclusion maps (criteria output 5)
# ============================================================
# panel titles follow the data: "soil" is named only when the soil rule (RX-8) actually excludes land
soil_excl <- "excl_terrain_vegetation" %in% names(EXL) && any(EXL$excl_terrain_vegetation$group == "soil")
GROUPS <- c(excl_environmental = "Environmental", excl_infrastructure = "Infrastructure", excl_land_use = "Land use",
            excl_terrain_vegetation = if (soil_excl) "Terrain, vegetation and soil" else "Terrain and vegetation")
soil_note <- if (soil_excl) "" else sprintf(" Soil rule (RX-8) checked: no unsuitable soil (%s) is mapped in Thimphu, so it excludes nothing and has no layer.",
                                             paste(unlist(RX$unsuitable_soil_patterns), collapse = ", "))
bbz <- st_bbox(dz); hsz <- mask(crop(hs, ext(bbz)), vect(dz)); hz <- as.data.frame(hsz, xy = TRUE, na.rm = TRUE); names(hz)[3] <- "hs"
epan <- lapply(names(GROUPS)[names(GROUPS) %in% names(EXL)], function(n) { x <- EXL[[n]]; x$label <- stringr::str_wrap(sprintf("%s [%s]", x$constraint, x$applies_to), 30)
  x <- x[order(-x$area_ha), ]; x$label <- factor(x$label, x$label)
  ggplot() + { if (FG$exclusion_basemap == "hillshade") list(geom_raster(data = hz, aes(x, y, fill = hs)), scale_fill_gradient(low = "#cfcfcf", high = "#ffffff", guide = "none"), ggnewscale::new_scale_fill()) } +
    geom_sf(data = dz, fill = NA, colour = "#555555", linewidth = 0.3) +
    geom_sf(data = x, aes(fill = label), colour = NA, alpha = 0.6) +
    scale_fill_viridis_d(option = "turbo", name = NULL) + fl_legend_layers(LS, 0.9) + marker_layers(2.2) + labs(title = GROUPS[n]) + theme_sci_map() +
    theme(legend.position = "right", legend.text = element_text(size = 6, lineheight = 0.85), legend.key.size = unit(0.32, "cm"),
          legend.key.spacing.y = unit(0.08, "cm"), plot.title = element_text(family = SCI$font, size = 9, face = "bold")) +
    guides(fill = guide_legend(ncol = 1, order = 2)) })
p5 <- wrap_plots(epan, ncol = 2)
save_fig(run, p5, 5, "exclusion_maps", S$exclusion_summary, c(
  "Mandatory exclusion zones for fire lines and prescribed burning in Thimphu dzongkhag.",
  "Each panel overlays the exclusion layers of one group, labelled with the activity they apply to in brackets; flagged layers (corridors, JDWNP/RBP for burning, recent burns) are shown but do not exclude; bold red lines = selected fire-line segments, yellow circles = selected burn sites; light hillshade from Copernicus GLO-30." |> paste0(soil_note),
  { es <- S$exclusion_summary; es <- es[!grepl("flag", es$constraint), ]; top <- es[order(-es$area_ha), ][1:2, ]
    sprintf("The largest exclusions are %s (%s ha) and %s (%s ha); all exclusion layers are supplied as shapefiles and KML (excl_*).",
            top$constraint[1], format(round(top$area_ha[1]), big.mark = ","), top$constraint[2], format(round(top$area_ha[2]), big.mark = ",")) }),
  size = c(7.2, 8.4))

# ============================================================
# FIGURE 6: score composition
# ============================================================
wf <- unlist(FL$weights)[COMP]; wf <- wf / sum(wf)
cl <- do.call(rbind, lapply(COMP, function(k) data.frame(unit = LS$segment, component = k, value = LS[[paste0("comp_", k)]] * wf[k])))
cl$unit <- factor(cl$unit, rev(LS$segment))
wr <- unlist(RX$weights); wr <- wr / sum(wr)
rc <- do.call(rbind, lapply(names(wr), function(k) data.frame(unit = RXS$site, component = k, value = RXS[[paste0("comp_", k)]] * wr[k])))
rc$unit <- factor(rc$unit, rev(RXS$site))
CC <- c(exposure = "#000000", fuel = "#E69F00", fire = "#D55E00", susceptibility = "#56B4E9", topography = "#009E73", access = "#CC79A7")
bar <- function(d) ggplot(d, aes(value, unit, fill = component)) + geom_col(colour = "black", linewidth = 0.2, width = 0.7) + scale_fill_manual(values = CC, name = NULL) +
  labs(x = "Weighted score contribution (0-1)", y = NULL) + theme_sci() + theme(legend.position = "bottom") + guides(fill = guide_legend(nrow = 2))
p6 <- (bar(cl) + bar(rc)) + plot_annotation(tag_levels = "a", tag_prefix = "(", tag_suffix = ")") & theme(plot.tag = element_text(family = SCI$font, size = 10))
save_fig(run, p6, 6, "score_components", rbind(cbind(set = "fire lines", cl), cbind(set = "burn sites", rc)), c(
  "Composition of the suitability score for each fire-line segment (a) and prescribed-burn site (b).",
  sprintf("Fire lines: weights %s; burn sites: weights %s (criteria document); each component is a 0-1 rank within Thimphu, computed only after the exclusions.",
          paste(sprintf("%s %.2f", COMP, wf), collapse = ", "), paste(sprintf("%s %.2f", names(wr), wr), collapse = ", ")),
  { mc <- sort(tapply(cl$value, cl$component, mean), decreasing = TRUE); mr <- sort(tapply(rc$value, rc$component, mean), decreasing = TRUE)
    sprintf("%s and %s contribute most to the fire-line scores, and %s and %s to the burn-site scores.", names(mc)[1], names(mc)[2], names(mr)[1], names(mr)[2]) }),
  size = c(7.2, 4.0))

# ============================================================
# FIGURE 7: weight sensitivity
# ============================================================
sv <- rbind(data.frame(scenario = SENS_FL$scenario, metric = "Fire-line segments kept (within 300 m)", value = SENS_FL$segments_retained_300m),
            data.frame(scenario = SENS_RX$scenario, metric = "Burn sites kept (within 500 m)", value = SENS_RX$rx_sites_within_500m / RX$n_sites))
sv$scenario <- factor(sv$scenario, rev(unique(c(SENS_FL$scenario, SENS_RX$scenario))))
p7 <- ggplot(sv, aes(value, scenario, shape = metric)) + geom_point(size = 2) + scale_shape_manual(values = c(16, 17), name = NULL) +
  scale_x_continuous(limits = c(0, 1), labels = function(x) paste0(100 * x, "%")) +
  labs(x = "Share of the base selection retained (%)", y = NULL) + theme_sci() + theme(legend.position = "bottom") + guides(shape = guide_legend(nrow = 2))
save_fig(run, p7, 7, "weight_sensitivity", sv, c(
  "Stability of the fire-line and burn-site selections when the scoring weights change.",
  "Each scenario reruns the full optimisation with equal weights, one weight doubled or one component dropped; segments count as kept if an alternative selection lies within 300 m, burn sites within 500 m.",
  sprintf("Burn sites keep a median %.0f%% and fire-line segments a median %.0f%% of the base selection; the weakest scenario for fire lines is \"%s\" (%.0f%% kept), so the segment list is best read as a ranked shortlist for field checking.",
          100 * median(SENS_RX$rx_sites_within_500m / RX$n_sites), 100 * median(SENS_FL$segments_retained_300m),
          SENS_FL$scenario[which.min(SENS_FL$segments_retained_300m)], 100 * min(SENS_FL$segments_retained_300m))),
  size = c(7.2, 4.6))

# ============================================================
# FIGURE 8: exclusion funnels
# ============================================================
ff <- funnel_fl[-1, ]; ff$rule <- factor(ff$rule, rev(ff$rule))
fr <- funnel[-1, ]; fr$rule <- factor(fr$rule, rev(unique(fr$rule)))
fa <- ggplot(ff, aes(cumulative_km, rule)) + geom_col(fill = "#888888", colour = "black", linewidth = 0.2, width = 0.65) +
  geom_text(aes(label = round(cumulative_km)), hjust = -0.15, family = SCI$font, size = 2.5) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.15))) + labs(x = "Candidate fire-line edge remaining (km)", y = NULL) + theme_sci()
fb <- ggplot(fr, aes(cumulative_ha, rule)) + geom_col(fill = "#888888", colour = "black", linewidth = 0.2, width = 0.65) +
  geom_text(aes(label = format(round(cumulative_ha), big.mark = ",")), hjust = -0.1, family = SCI$font, size = 2.5) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.2)), labels = scales::comma) + labs(x = "Land eligible for burning remaining (ha)", y = NULL) + theme_sci()
p8 <- (fa / fb) + plot_layout(heights = c(nrow(ff), nrow(fr))) + plot_annotation(tag_levels = "a", tag_prefix = "(", tag_suffix = ")") & theme(plot.tag = element_text(family = SCI$font, size = 10))
save_fig(run, p8, 8, "exclusion_funnels", rbind(data.frame(set = "fire lines", rule = funnel_fl$rule, remaining = funnel_fl$cumulative_km, unit = "km"),
                                                data.frame(set = "burning", rule = funnel$rule, remaining = funnel$cumulative_ha, unit = "ha")), c(
  "Candidate fire-line edge (a) and land eligible for prescribed burning (b) remaining after each mandatory exclusion is applied in turn.",
  "Rules follow the order of the criteria document and are applied cumulatively before any scoring; fire-line rules act on 100 m pieces of the settlement edge, burning rules on 50 m cells.",
  { d1 <- -diff(funnel_fl$cumulative_km); names(d1) <- funnel_fl$rule[-1]; d2 <- -diff(funnel$cumulative_ha); names(d2) <- funnel$rule[-1]
    sprintf("%.0f of %.0f km of edge survive for fire lines (largest cut: \"%s\") and %.0f ha survive for burning (largest cut after vegetation type: \"%s\").",
            tail(funnel_fl$cumulative_km, 1), funnel_fl$cumulative_km[1], names(which.max(d1)), tail(funnel$cumulative_ha, 1), names(sort(d2, decreasing = TRUE))[2]) }),
  size = c(7.2, 7.4))

# ============================================================
# PROCESS DATA + REPORT
# ============================================================
write_process(run, tl, "fire_lines_table")
write_process(run, st_drop_geometry(RXS), "rx_burn_sites_table")
write_process(run, S$COMPARE, "comparative_selected_sites")
write_process(run, funnel_fl, "fire_line_exclusion_funnel")
write_process(run, funnel, "rx_eligibility_funnel")
write_process(run, S$exclusion_summary, "exclusion_layers_summary")
write_process(run, SENS_FL, "sensitivity_fire_lines")
write_process(run, SENS_RX, "sensitivity_rx_sites")
write_process(run, pk, "candidate_line_pieces")
build_report(run, intro = c(
  sprintf("Proposed fire lines (%d segments, %s m, %s) and seven prescribed-burn sites (%.0f ha) for fuel hazard reduction at the wildland-urban interface of Thimphu dzongkhag, following the DoFPS criteria document (refined 2026-11-26).",
          nrow(LS), format(sum(LS$built_length_m), big.mark = ","), paste(unique(LS$width_m_mix), collapse = ", "), sum(RXS$area_ha)),
  sprintf("Mandatory exclusions (including the DoFPS no-go areas: %s) were applied before scoring; selections were optimised for total length/area, spacing and anchoring.", paste(nogo$name, collapse = "; ")),
  "All lines and sites are desk-selected candidates on 50-100 m data and must be verified in the field (field validation protocol) before clearing or burning."))
# openxlsx in this environment leaves dangling drawing links; repair any workbooks written by this run
py <- Sys.which(c("python", "python3")); py <- py[nzchar(py)][1]
xl <- list.files(run$dir, "\\.xlsx$", recursive = TRUE, full.names = TRUE)
if (!is.na(py) && length(xl)) system2(py, c("-I", shQuote(tw("scripts/fix_xlsx.py")), shQuote(xl)))
message("Figures and report: ", run$dir)
