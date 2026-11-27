# 03  Fire-based calibration of the WUI criteria for Thimphu dzongkhag
# The US criteria put nearly every building in WUI, so they cannot rank exposure. Here every combination of the
# sensitivity grid (D x V x P x R x A x 3 vegetation definitions = 2,160 rules) is scored against observed fire:
#   a building is "fire-exposed" when fire evidence (2012-2025) lies within the exposure distance (1 km primary);
#   fire evidence = DoFPS incident points + satellite-mapped burned patches ("records") and FIRMS detections ("firms").
#   Score = Youden J = sensitivity + specificity - 1 of "building in WUI" for "building fire-exposed".
# The rule with the highest J on all evidence at 1 km is selected (ties -> fewest changes from the baseline).
# Honest skill: leave-one-gewog-out cross-validation re-selects the rule without each unit and scores it on that unit.
# Robustness: J of the selected rule under each evidence set and exposure distance; cluster bootstrap by unit.
# Outputs: data/derived/wui_class_calibrated_50m.tif, wui_thimphu.gpkg (classes, buildings), results_calibration.json
# Run: Rscript thimphu_WUI/scripts/03_fire_calibration.R   (after 02)
source(if (file.exists("thimphu_WUI/R/tw_common.R")) "thimphu_WUI/R/tw_common.R" else "R/tw_common.R")
source(tw("R/sci_figure.R")); suppressPackageStartupMessages({ library(patchwork) })
terraOptions(memfrac = 0.5, progress = 0)
set.seed(20261123)
# ============================================================
# CONFIGURATION
# ============================================================
SLUG <- "02-calibration"
TITLE <- "Fire-based calibration of the wildland-urban interface criteria, Thimphu"
G <- CFG$sensitivity_grid; B <- CFG$baseline; FE <- CFG$fire_evidence; CONF <- CFG$buildings$confidence_min
LAY <- tw("data/derived/layers"); DMAIN <- FE$exposure_distance_m; DIST <- FE$exposure_distance_test
SETS <- c("records", "firms", "all"); N_BOOT <- 1000
# ============================================================
# Reuse the existing output tree; overwrite generated files without recreating folders.
run <- sci_run(SLUG, TITLE, inputs = c(file.path(LAY, "x"), tw("data/inputs/x")))
g <- grid50(); zone <- values(g, mat = FALSE); inside <- which(zone %in% 2)
gid <- rast(tw("data/inputs/gewog_50m.tif")); glev <- levels(gid)[[1]]
unit_of_cell <- glev[[2]][match(values(gid, mat = FALSE), glev[[1]])]
ob <- st_read(tw("data/inputs/buildings.gpkg"), "open_buildings_v3", quiet = TRUE); ob <- ob[ob$confidence >= CONF, ]
bcell <- cellFromXY(g, st_coordinates(ob)); keep <- !is.na(bcell) & zone[bcell] %in% 2
ob <- ob[keep, ]; bcell <- bcell[keep]; bidx <- match(bcell, inside); bunit <- unit_of_cell[bcell]
bunit[is.na(bunit)] <- CFG$study_area$unassigned_unit
nb <- nrow(ob)

# ---- fire evidence: distance from every building to the nearest evidence of each set -----------------------------------
fe_path <- tw("data/inputs/fire_evidence.gpkg")
dp <- st_read(fe_path, "dofps_points", quiet = TRUE); fp <- st_read(fe_path, "firms_points", quiet = TRUE)
bp <- st_read(fe_path, "burned_patches", quiet = TRUE)
ev_r <- function(layers) { r <- rast(g); values(r) <- NA
  for (x in layers) { y <- if (all(st_geometry_type(x) %in% c("POINT", "MULTIPOINT"))) rasterize(vect(x), g, field = 1) else rasterize(vect(x), g, field = 1, touches = TRUE)
    r <- cover(r, y) }
  r }
EV <- list(records = ev_r(list(dp, bp)), firms = ev_r(list(fp))); EV$all <- cover(EV$records, EV$firms)
DISTR <- lapply(EV, distance)
bdist <- sapply(DISTR, function(r) values(r, mat = FALSE)[bcell])
EXP <- list(); for (s in SETS) for (d in DIST) EXP[[paste(s, d, sep = "@")]] <- bdist[, s] <= d
cell_ev <- lapply(EV, function(r) !is.na(values(r, mat = FALSE)[inside]))

# ---- score every rule -------------------------------------------------------------------------------------------------
vals <- function(r) values(r, mat = FALSE)[inside]
DEN <- lapply(setNames(G$R, G$R), function(r) vals(rast(file.path(LAY, "density_ob.tif"))[[paste0("r", r)]]))
VP <- lapply(setNames(G$veg, G$veg), function(v) lapply(setNames(G$R, G$R), function(r) vals(rast(file.path(LAY, sprintf("vegpct_%s.tif", v)))[[paste0("r", r)]])))
PD <- lapply(setNames(G$veg, G$veg), function(v) lapply(setNames(G$A, G$A), function(a) vals(rast(file.path(LAY, sprintf("patchdist_%s.tif", v)))[[paste0("a", a)]])))
grid <- expand.grid(D = G$D, V = G$V, P = G$P, R = G$R, A = G$A, veg = G$veg, stringsAsFactors = FALSE)
youden <- function(w, e) { tp <- sum(w & e); fn <- sum(!w & e); fp <- sum(w & !e); tn <- sum(!w & !e)
  c(sens = tp / (tp + fn), spec = tn / (tn + fp), J = tp / (tp + fn) + tn / (tn + fp) - 1) }
WB <- matrix(FALSE, nb, nrow(grid))
res <- vector("list", nrow(grid))
for (i in seq_len(nrow(grid))) { x <- grid[i, ]; rk <- as.character(x$R)
  d <- DEN[[rk]]; v <- VP[[x$veg]][[rk]]; p <- PD[[x$veg]][[as.character(x$A)]]
  ok <- !is.na(d) & !is.na(v); dense <- ok & d > x$D
  wui <- dense & (v >= x$V | (!is.na(p) & p <= x$P)); inter <- dense & v >= x$V
  wb <- wui[bidx]; WB[, i] <- wb
  m <- c(wui_km2 = sum(wui) * (RES / 1000)^2, intermix_km2 = sum(inter) * (RES / 1000)^2, wui_buildings = sum(wb), building_share = mean(wb))
  for (k in names(EXP)) { y <- youden(wb, EXP[[k]]); m[paste0("J_", k)] <- y[["J"]]; m[paste0("sens_", k)] <- y[["sens"]]; m[paste0("spec_", k)] <- y[["spec"]] }
  for (s in SETS) { ce <- cell_ev[[s]]; m[paste0("enrich_", s)] <- (sum(ce & wui) / max(1, sum(wui))) / (sum(ce & !wui & ok) / max(1, sum(!wui & ok))) }
  res[[i]] <- m }
SC <- cbind(grid, do.call(rbind, res))
key <- paste0("J_all@", DMAIN)
nchg <- (SC$D != B$D) + (SC$V != B$V) + (SC$P != B$P) + (SC$R != B$R) + (SC$A != B$A) + (SC$veg != B$veg)
ord <- order(-round(SC[[key]], 6), nchg, SC$wui_km2)
SEL <- SC[ord[1], ]; BASE_ROW <- SC[which(nchg == 0), ]
SC$rank <- NA; SC$rank[ord] <- seq_along(ord)
message(sprintf("Selected: D %.2f V %d P %d R %d A %g veg %s | J %.3f (baseline %.3f) | WUI %.0f km2, %.0f%% of buildings",
                SEL$D, SEL$V, SEL$P, SEL$R, SEL$A, SEL$veg, SEL[[key]], BASE_ROW[[key]], SEL$wui_km2, 100 * SEL$building_share))

# ---- honest skill: leave-one-unit-out cross-validation -------------------------------------------------------------------
units <- sort(unique(bunit)); E0 <- EXP[[paste0("all@", DMAIN)]]
cv <- do.call(rbind, lapply(units, function(u) { tr <- bunit != u; te <- !tr
  jt <- apply(WB[tr, , drop = FALSE], 2, function(w) youden(w, E0[tr])[["J"]])
  best <- order(-round(jt, 6), nchg, SC$wui_km2)[1]
  data.frame(unit = u, n_test = sum(te), exposed_test = sum(E0[te]), chosen_rule = best, chosen_is_selected = best == ord[1],
             tp = sum(WB[te, best] & E0[te]), fn = sum(!WB[te, best] & E0[te]), fp = sum(WB[te, best] & !E0[te]), tn = sum(!WB[te, best] & !E0[te])) }))
cv_J <- with(cv, sum(tp) / (sum(tp) + sum(fn)) + sum(tn) / (sum(tn) + sum(fp)) - 1)

# ---- robustness and bootstrap -----------------------------------------------------------------------------------------------
rob <- do.call(rbind, lapply(names(EXP), function(k) data.frame(set = sub("@.*", "", k), distance_m = as.integer(sub(".*@", "", k)),
  rule = c("Selected (calibrated)", "Baseline (US criteria)"), J = c(SEL[[paste0("J_", k)]], BASE_ROW[[paste0("J_", k)]]),
  percentile_of_selected = mean(SC[[paste0("J_", k)]] <= SEL[[paste0("J_", k)]]), exposed_share = mean(EXP[[k]]))))
wsel <- WB[, ord[1]]; wbase <- WB[, which(nchg == 0)]
boot <- t(replicate(N_BOOT, { us <- sample(units, length(units), replace = TRUE); ix <- unlist(lapply(us, function(u) which(bunit == u)))
  c(sel = youden(wsel[ix], E0[ix])[["J"]], base = youden(wbase[ix], E0[ix])[["J"]]) }))
boot_ci <- apply(cbind(boot, diff = boot[, "sel"] - boot[, "base"]), 2, quantile, c(.025, .975), na.rm = TRUE)

# ---- final classification and spatial products ------------------------------------------------------------------------------
x <- SEL; rk <- as.character(x$R)
cal_cl <- classify_wui(DEN[[rk]], VP[[x$veg]][[rk]], ifelse(is.na(PD[[x$veg]][[as.character(x$A)]]), Inf, PD[[x$veg]][[as.character(x$A)]]), x$D, x$V, x$P)
fill <- function(v) { r <- rast(g); xx <- rep(NA_real_, ncell(g)); xx[inside] <- v; values(r) <- xx; r }
cal_r <- fill(cal_cl); levels(cal_r) <- data.frame(value = 1:5, class = CLASSES)
writeRaster(cal_r, tw("data/derived/wui_class_calibrated_50m.tif"), overwrite = TRUE, datatype = "INT1U", gdal = "COMPRESS=DEFLATE")
base_r <- rast(tw("data/derived/wui_class_baseline_50m.tif")); base_cl <- values(base_r, mat = FALSE)[inside]
ob$class_calibrated <- CLASSES[cal_cl[bidx]]; ob$class_baseline <- CLASSES[base_cl[bidx]]; ob$unit <- bunit
for (s in SETS) ob[[paste0("dist_fire_", s, "_m")]] <- round(bdist[, s])
gpkg <- tw("data/derived/wui_thimphu.gpkg"); if (file.exists(gpkg)) file.remove(gpkg)
pol <- st_as_sf(as.polygons(cal_r)); names(pol)[1] <- "class"; pol$area_km2 <- as.numeric(st_area(pol)) / 1e6
st_write(pol, gpkg, "wui_classes_calibrated", quiet = TRUE)
polb <- st_as_sf(as.polygons(base_r)); names(polb)[1] <- "class"; polb$area_km2 <- as.numeric(st_area(polb)) / 1e6
st_write(polb, gpkg, "wui_classes_baseline", quiet = TRUE, append = TRUE)
st_write(ob[, c("confidence", "area_m2", "unit", "class_calibrated", "class_baseline", paste0("dist_fire_", SETS, "_m"))], gpkg, "buildings", quiet = TRUE, append = TRUE)
write.csv(SC, tw("data/derived/calibration_all_rules.csv"), row.names = FALSE)

# ============================================================
# DATA HEALTH
# ============================================================
data_health(run, data.frame(dist_records_m = bdist[, "records"], dist_firms_m = bdist[, "firms"], dist_all_m = bdist[, "all"], unit = bunit), "Buildings: distance to nearest fire evidence")
data_health(run, SC[, c("wui_km2", "building_share", key, "J_records@1000", "J_firms@1000", "enrich_all")], "Scores of all 2,160 rules")
write_health(run, notes = c(
  sprintf("Fire evidence 2012-2025 in the Thimphu buffer: %d DoFPS incident points, %d burned patches (%.0f ha), %d FIRMS detections.", nrow(dp), nrow(bp), sum(bp$area_ha), nrow(fp)),
  sprintf("%s buildings inside Thimphu; %.0f%% have fire evidence within %d m (all evidence).", format(nb, big.mark = ","), 100 * mean(E0), DMAIN),
  "Fire evidence is clustered near settlements because most ignitions are human; that link between people and burnable vegetation is what the WUI is meant to capture, so it is the calibration target rather than a bias.",
  "FIRMS detections can include agricultural and debris burning; the records-only evidence set (DoFPS + mapped burned patches) is reported as a check.",
  sprintf("Selection over %d rules is optimistic, so leave-one-unit-out cross-validation (%d units) is reported as the honest skill.", nrow(SC), length(units))))

# ============================================================
# FIGURES
# ============================================================
dz <- study_dz(); gw <- study_gewogs()
# Fig 1 fire evidence
obs <- ob[sample(nb, min(nb, 15000)), ]
p1 <- ggplot() + geom_sf(data = gw, fill = NA, colour = "#bbbbbb", linewidth = 0.25) +
  geom_sf(data = obs, colour = "#9e9e9e", size = 0.05, alpha = 0.5) +
  geom_sf(data = bp, fill = "#a50026", colour = "#a50026", linewidth = 0.2) +
  geom_sf(data = fp, aes(shape = "FIRMS detection"), size = 0.6, colour = "#E69F00") +
  geom_sf(data = dp, aes(shape = "DoFPS incident"), size = 1.6, colour = "black") +
  geom_sf(data = dz, fill = NA, colour = "black", linewidth = 0.5) +
  scale_shape_manual(values = c(`DoFPS incident` = 17, `FIRMS detection` = 16), name = NULL) +
  ggspatial::annotation_scale(location = "bl", text_family = SCI$font, height = unit(0.15, "cm")) + theme_sci_map() + theme(legend.position = "bottom")
save_fig(run, p1, 1, "fire_evidence", data.frame(set = c("DoFPS points", "burned patches", "FIRMS"), n = c(nrow(dp), nrow(bp), nrow(fp))), c(
  sprintf("Fire evidence used to calibrate the WUI criteria in Thimphu, 2012-2025: %d DoFPS incident points, %d satellite-mapped burned patches (dark red) and %d FIRMS detections.", nrow(dp), nrow(bp), nrow(fp)),
  "Grey dots are Open Buildings V3 footprints (random sample of up to 15,000); burned patches come from the thimphu_paro_burn_severity package; FIRMS filtered to nominal/high confidence and presumed vegetation fires.",
  sprintf("%.0f%% of Thimphu buildings have fire evidence within %d m, so fire reaches most settlements and a useful WUI rule must single out the minority of buildings that fire rarely reaches.", 100 * mean(E0), DMAIN)),
  size = c(6.5, 6.4))

# Fig 2 J versus proximity
cur <- aggregate(as.formula(paste0("`", key, "` ~ P + R + veg")), SC, max); names(cur)[4] <- "J"
cur$veg <- factor(VEG_LABEL[cur$veg], VEG_LABEL); cur$R <- factor(paste(cur$R, "m"), paste(G$R, "m"))
p2 <- ggplot(cur, aes(P, J, linetype = R, shape = R)) + geom_line(linewidth = 0.45) + geom_point(size = 1.6) +
  scale_x_log10(breaks = G$P) + facet_wrap(~ veg) +
  geom_point(data = data.frame(P = SEL$P, J = SEL[[key]], veg = factor(VEG_LABEL[[SEL$veg]], VEG_LABEL)), aes(P, J),   # only in the selected panel
             inherit.aes = FALSE, shape = 1, size = 5, stroke = 0.8) +
  labs(x = "Proximity to a large vegetated patch, P (m)", y = "Youden J (best over D, V, A)", linetype = "Radius R", shape = "Radius R") +
  theme_sci() + theme(legend.position = "bottom")
save_fig(run, p2, 2, "skill_by_proximity", cur, c(
  sprintf("Skill of WUI rules at identifying fire-exposed buildings in Thimphu (fire evidence within %d m), by proximity distance, neighbourhood radius and wildland-vegetation definition.", DMAIN),
  "Youden J = sensitivity + specificity - 1 of building WUI membership; each point is the best J over density, vegetation-cover and patch-size thresholds; the circle marks the selected rule.",
  sprintf("Skill peaks at P = %d m with a %d m radius and %s; the US rules (J %.2f) also sweep in the dense city core and isolated buildings, which fire reaches less often, whereas the calibrated rule leaves them out (J %.2f).",
          SEL$P, SEL$R, VEG_LABEL[[SEL$veg]], BASE_ROW[[key]], SEL[[key]])),
  size = c(7.2, 3.8))

# Fig 3 trade-off: WUI area vs skill
SC$vegl <- factor(VEG_LABEL[SC$veg], VEG_LABEL)
p3 <- ggplot(SC, aes(wui_km2, .data[[key]], shape = vegl)) + geom_point(colour = "#9e9e9e", size = 1) +
  annotate("point", x = BASE_ROW$wui_km2, y = BASE_ROW[[key]], shape = 23, size = 3.5, fill = "white", stroke = 0.8) +
  annotate("point", x = SEL$wui_km2, y = SEL[[key]], shape = 8, size = 3.5, stroke = 0.9) +
  annotate("text", x = BASE_ROW$wui_km2, y = BASE_ROW[[key]], label = "US baseline", hjust = -0.15, size = 3, family = SCI$font) +
  annotate("text", x = SEL$wui_km2, y = SEL[[key]], label = "selected", hjust = -0.25, size = 3, family = SCI$font) +
  scale_shape_manual(values = c(1, 2, 0), name = NULL) + labs(x = "WUI area in Thimphu (km2)", y = sprintf("Youden J (all evidence, %d m)", DMAIN)) +
  theme_sci() + theme(legend.position = "bottom")
save_fig(run, p3, 3, "skill_vs_area", SC[, c("D", "V", "P", "R", "A", "veg", "wui_km2", "building_share", key)], c(
  sprintf("WUI area and skill of all %s candidate rules for Thimphu.", format(nrow(SC), big.mark = ",")),
  sprintf("Each grey point is one combination of density, vegetation cover, proximity, radius, patch size and vegetation definition; star = selected rule, diamond = US baseline; skill is Youden J for fire evidence within %d m.", DMAIN),
  sprintf("The selected rule maps %.0f km2 and %.0f%% of buildings as WUI against %.0f km2 and %.0f%% under the US criteria: WUI area hardly changes, but %s fewer buildings count as WUI, mostly in the dense city core and isolated low-density settlement.",
          SEL$wui_km2, 100 * SEL$building_share, BASE_ROW$wui_km2, 100 * BASE_ROW$building_share, format(round(nb * (BASE_ROW$building_share - SEL$building_share)), big.mark = ","))),
  size = c(5.5, 4.2))

# Fig 4 robustness
rob$set_label <- factor(c(records = "Records (DoFPS + patches)", firms = "FIRMS", all = "All evidence")[rob$set], c("Records (DoFPS + patches)", "FIRMS", "All evidence"))
p4 <- ggplot(rob, aes(factor(distance_m), J, shape = rule)) + geom_hline(yintercept = 0, linetype = "dashed") + geom_point(size = 2.2, position = position_dodge(0.4)) +
  facet_wrap(~ set_label) + scale_shape_manual(values = c(`Selected (calibrated)` = 16, `Baseline (US criteria)` = 5), name = NULL) +
  labs(x = "Exposure distance (m)", y = "Youden J") + theme_sci() + theme(legend.position = "bottom")
save_fig(run, p4, 4, "robustness", rob, c(
  "Skill of the selected and baseline WUI rules in Thimphu under each fire-evidence set and exposure distance.",
  sprintf("Youden J of building WUI membership; leave-one-unit-out cross-validated J of the selection procedure = %.2f (in-sample %.2f); cluster bootstrap by unit (%d replicates): J difference selected minus baseline %.2f (95%% CI %.2f to %.2f).",
          cv_J, SEL[[key]], N_BOOT, SEL[[key]] - BASE_ROW[[key]], boot_ci[1, "diff"], boot_ci[2, "diff"]),
  sprintf("The selected rule beats the US baseline in %d of %d evidence-distance combinations; cross-validated J (%.2f) is %.0f%% of the in-sample value but still %.1f times the baseline, so part of the gain is real and part reflects choosing among %s rules.",
          sum(rob$J[rob$rule == "Selected (calibrated)"] > rob$J[rob$rule == "Baseline (US criteria)"]), nrow(rob) / 2, cv_J, 100 * cv_J / SEL[[key]], cv_J / BASE_ROW[[key]], format(nrow(SC), big.mark = ","))),
  size = c(7.2, 3.6))

# Fig 5 maps baseline vs calibrated
md <- rbind(data.frame(as.data.frame(mask(base_r, vect(dz)), xy = TRUE, na.rm = TRUE) |> setNames(c("x", "y", "class")), map = "US baseline criteria"),
            data.frame(as.data.frame(mask(cal_r, vect(dz)), xy = TRUE, na.rm = TRUE) |> setNames(c("x", "y", "class")), map = "Calibrated to Thimphu fire evidence"))
md$class <- factor(md$class, CLASSES); md$map <- factor(md$map, unique(md$map))
p5 <- ggplot() + geom_raster(data = md, aes(x, y, fill = class)) + scale_fill_manual(values = WUI_COLS, name = NULL, drop = FALSE) +
  geom_sf(data = dz, fill = NA, colour = "black", linewidth = 0.4) + facet_wrap(~ map) + theme_sci_map() + theme(legend.position = "bottom")
cal_tab <- data.frame(class = CLASSES, area_km2 = vapply(1:5, function(k) sum(cal_cl == k, na.rm = TRUE), 0) * (RES / 1000)^2,
                      buildings = vapply(1:5, function(k) sum(cal_cl[bidx] %in% k), 0))
save_fig(run, p5, 5, "wui_map_calibrated", cal_tab, c(
  "Wildland-urban interface of Thimphu dzongkhag under the US baseline criteria and under the rule calibrated to local fire evidence.",
  sprintf("Calibrated rule: density > %.2f buildings/km2, vegetation >= %d%% (%s), within %d m of a >= %g km2 vegetated patch, %d m neighbourhood; 50 m grid.", SEL$D, SEL$V, VEG_LABEL[[SEL$veg]], SEL$P, SEL$A, SEL$R),
  sprintf("%.0f%% of WUI buildings are intermix (%s) and %s interface: Thimphu's houses are scattered through grass, scrub and forest rather than facing wildland along one edge, so WUI management is landscape-wide, and the calibrated map's main contribution is to set aside the %s buildings of the dense core and isolated settlement where fire is recorded less often.",
          100 * cal_tab$buildings[1] / sum(cal_tab$buildings[1:2]), format(cal_tab$buildings[1], big.mark = ","), format(cal_tab$buildings[2], big.mark = ","),
          format(sum(cal_tab$buildings[3:5]), big.mark = ","))),
  size = c(7.2, 5.2))

# Fig 6 exposure rate by class
er <- do.call(rbind, lapply(c("calibrated", "baseline"), function(m) { cl <- if (m == "calibrated") cal_cl[bidx] else base_cl[bidx]
  do.call(rbind, lapply(1:5, function(k) { s <- cl %in% k; if (!any(s)) return(NULL); ci <- wilson_ci(sum(E0[s]), sum(s))
    data.frame(map = m, class = CLASSES[k], n = sum(s), exposed = sum(E0[s]), rate = mean(E0[s]), low = ci[1], high = ci[2]) })) }))
er$class <- factor(er$class, CLASSES); er$map <- factor(ifelse(er$map == "calibrated", "Calibrated", "US baseline"), c("US baseline", "Calibrated"))
p6 <- ggplot(er, aes(class, rate, fill = map)) + geom_col(position = position_dodge(0.75), width = 0.7, colour = "black", linewidth = 0.25) +
  geom_errorbar(aes(ymin = low, ymax = high), position = position_dodge(0.75), width = 0.2, linewidth = 0.35) +
  geom_text(aes(y = high, label = paste0("n=", format(n, big.mark = ","))), position = position_dodge(0.75), vjust = -0.4, size = 2.3, family = SCI$font) +
  scale_fill_manual(values = c(`US baseline` = "#ffffff", Calibrated = "#888888"), name = NULL) + scale_y_continuous(labels = scales::percent, limits = c(0, 1.1)) +
  labs(x = NULL, y = sprintf("Buildings with fire evidence within %d m (%%)", DMAIN)) + theme_sci() + theme(legend.position = "bottom", axis.text.x = element_text(size = 8))
r_in <- with(er[er$map == "Calibrated", ], sum(exposed[class %in% c("intermix", "interface")]) / sum(n[class %in% c("intermix", "interface")]))
r_out <- with(er[er$map == "Calibrated", ], sum(exposed[!class %in% c("intermix", "interface")]) / sum(n[!class %in% c("intermix", "interface")]))
save_fig(run, p6, 6, "exposure_rate_by_class", er, c(
  sprintf("Share of Thimphu buildings with fire evidence within %d m by WUI class, under the US baseline and the calibrated rule.", DMAIN),
  "Bars show shares with Wilson 95% CI; labels give building counts per class.",
  sprintf("Under the calibrated rule %.0f%% of WUI buildings have nearby fire evidence against %.0f%% of non-WUI buildings (%.1f times higher), so the calibrated classes separate exposed from sheltered settlement.", 100 * r_in, 100 * r_out, r_in / r_out)),
  size = c(7.2, 3.8))

top <- head(SC[ord, c("D", "V", "P", "R", "A", "veg", "wui_km2", "building_share", key, "J_records@1000", "J_firms@1000")], 15)
write_process(run, top, "top15_rules")
write_process(run, SC[, setdiff(names(SC), "vegl")], "all_rules_scores")
write_process(run, rob, "robustness")
write_process(run, cv, "cross_validation_by_unit")
write_process(run, data.frame(statistic = c("J selected", "J baseline", "J difference"), low = boot_ci[1, ], high = boot_ci[2, ]), "bootstrap_ci")
write_process(run, cal_tab, "calibrated_class_area_buildings")
write_json_pretty(list(selected = as.list(SEL[, c("D", "V", "P", "R", "A", "veg")]), J_selected = SEL[[key]], J_baseline = BASE_ROW[[key]], cv_J = cv_J,
                       cv_units_choosing_same_rule = sum(cv$chosen_is_selected), n_units = length(units), boot_ci = boot_ci,
                       selected_wui_km2 = SEL$wui_km2, selected_building_share = SEL$building_share, baseline_wui_km2 = BASE_ROW$wui_km2,
                       baseline_building_share = BASE_ROW$building_share, exposed_share_buildings = mean(E0), rate_wui = r_in, rate_non_wui = r_out,
                       n_rules = nrow(SC), robustness = rob, calibrated_classes = cal_tab, n_buildings = nb,
                       evidence = list(dofps = nrow(dp), patches = nrow(bp), patches_ha = sum(bp$area_ha), firms = nrow(fp))), tw("data/derived/results_calibration.json"))
build_report(run, intro = c(
  sprintf("The US WUI criteria classify %.0f%% of Thimphu buildings as WUI. Scoring %s rules against 2012-2025 fire evidence selects density > %.2f/km2, vegetation >= %d%% (%s), proximity %d m, radius %d m, patch %g km2.",
          100 * BASE_ROW$building_share, format(nrow(SC), big.mark = ","), SEL$D, SEL$V, VEG_LABEL[[SEL$veg]], SEL$P, SEL$R, SEL$A),
  sprintf("Youden J rises from %.2f to %.2f (cross-validated %.2f); the calibrated WUI covers %.0f km2 and %.0f%% of buildings.", BASE_ROW[[key]], SEL[[key]], cv_J, SEL$wui_km2, 100 * SEL$building_share)))
print(top[1:5, ]); print(rob)
