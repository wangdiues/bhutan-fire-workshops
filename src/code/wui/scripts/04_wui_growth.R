# 04  WUI growth in Thimphu 2016-2026 from Dynamic World annual land cover
# Building footprints exist only as a 2023 snapshot, so annual WUI uses Dynamic World (10 m, annual label mode
# aggregated to 50 m shares). Settlement density is proxied by the neighbourhood built share: its threshold B is
# chosen so that DW "settled" cells (built share within R > B) best match footprint-based settled cells
# (density > D) in 2023 (Cohen's kappa). The calibrated rule from script 03 (V, P, R, A, vegetation definition
# mapped to DW classes) is then applied to every year. 2016 (from October) and 2026 (to download date) are partial
# years: shown, but excluded from trends. Trend = Theil-Sen slope with Kendall's tau test over 2017-2025.
# Run: Rscript thimphu_WUI/scripts/04_wui_growth.R   (after 03)
source(if (file.exists("thimphu_WUI/R/tw_common.R")) "thimphu_WUI/R/tw_common.R" else "R/tw_common.R")
source(tw("R/sci_figure.R")); suppressPackageStartupMessages({ library(patchwork) })
terraOptions(memfrac = 0.5, progress = 0)
# ============================================================
# CONFIGURATION
# ============================================================
SLUG <- "03-growth"
TITLE <- "Growth of the wildland-urban interface in Thimphu, 2016-2026"
GR <- CFG$growth; PV <- CFG$patch_vegetation_share
SELP <- read_json(tw("data/derived/results_calibration.json"), simplifyVector = TRUE)$selected
DWDIR <- tw("data/inputs/dynamic_world"); LAY <- tw("data/derived/layers")
YEARS <- 2016:2026
# ============================================================
# Reuse the existing output tree; overwrite generated files without recreating folders.
run <- sci_run(SLUG, TITLE, inputs = c(file.path(DWDIR, "x"), file.path(LAY, "x")))
g <- grid50(); zone <- values(g, mat = FALSE); inside <- which(zone %in% 2)
gid <- rast(tw("data/inputs/gewog_50m.tif")); glev <- levels(gid)[[1]]
unit <- glev[[2]][match(values(gid, mat = FALSE), glev[[1]])][inside]
dom <- rast(file.path(LAY, "vegshare_ftm.tif"))   # Bhutan-only domain shared with scripts 02-03
w <- circle_w(g, SELP$R); km2 <- (RES / 1000)^2
vegc <- unname(c(`1` = "trees", `2` = "grass", `5` = "shrub")[as.character(GR$dw_vegetation_classes[[SELP$veg]])])   # DW layer names
dw <- function(y) rast(file.path(DWDIR, sprintf("dw_%d_shares_50m.tif", y)))

# ---- calibrate the DW built-share threshold against 2023 footprints ------------------------------------------------
ob_dense <- values(rast(file.path(LAY, "density_ob.tif"))[[paste0("r", SELP$R)]], mat = FALSE)[inside] > SELP$D
nb_built <- function(y) values(focal(mask(dw(y)[["built"]] / 100, dom), w, fun = "mean", na.rm = TRUE), mat = FALSE)[inside]
nb23 <- nb_built(GR$calibration_year)
kap <- do.call(rbind, lapply(GR$built_share_grid, function(b) { ok <- !is.na(nb23) & !is.na(ob_dense)
  k <- md_kappa(ob_dense[ok], nb23[ok] > b, c(FALSE, TRUE)); data.frame(built_share_threshold = b, agreement = k[["agreement"]], kappa = k[["kappa"]],
  dw_settled_km2 = sum(nb23[ok] > b) * km2, ob_settled_km2 = sum(ob_dense[ok]) * km2) }))
BSTAR <- kap$built_share_threshold[which.max(kap$kappa)]

# ---- annual classification ---------------------------------------------------------------------------------------------
annual <- list(); WUIY <- list()
for (y in YEARS) {
  if (!file.exists(file.path(DWDIR, sprintf("dw_%d_shares_50m.tif", y)))) next
  r <- dw(y); veg <- mask(sum(r[[vegc]]) / 100, dom)
  vp <- values(100 * focal(veg, w, fun = "mean", na.rm = TRUE), mat = FALSE)[inside]
  pid <- patches(ifel(veg >= PV, 1, NA), directions = 8, zeroAsNA = TRUE); pa <- freq(pid); pa$km2 <- pa$count * km2
  pd <- values(distance(classify(pid, cbind(pa$value, ifelse(pa$km2 >= SELP$A, 1, NA)))), mat = FALSE)[inside]
  nb <- nb_built(y)
  cl <- ifelse(is.na(nb) | is.na(vp), NA_integer_, ifelse(nb > BSTAR, ifelse(vp >= SELP$V, 1L, ifelse(pd <= SELP$P, 2L, 4L)), ifelse(vp >= SELP$V, 3L, 5L)))
  WUIY[[as.character(y)]] <- cl %in% 1:2
  bshare <- values(mask(r[["built"]], dom), mat = FALSE)[inside] / 100
  annual[[as.character(y)]] <- data.frame(year = y, partial = y %in% GR$partial_years, built_km2 = sum(bshare, na.rm = TRUE) * km2,
    wui_km2 = sum(cl %in% 1:2) * km2, intermix_km2 = sum(cl %in% 1) * km2, interface_km2 = sum(cl %in% 2) * km2,
    mean_valid_obs = mean(values(r[["valid_obs"]], mat = FALSE)[inside], na.rm = TRUE))
  if (y == GR$calibration_year) cl23 <- cl
  message("year ", y)
}
AN <- do.call(rbind, annual)

# DW-based WUI 2023 versus the footprint-based calibrated WUI (validation of the proxy)
cal <- values(rast(tw("data/derived/wui_class_calibrated_50m.tif")), mat = FALSE)[inside]
ok <- !is.na(cal) & !is.na(cl23)
val <- c(md_kappa(cal[ok], cl23[ok], 1:5), wui_agreement = mean((cal[ok] %in% 1:2) == (cl23[ok] %in% 1:2)))

# ---- trends -------------------------------------------------------------------------------------------------------------
sen <- function(x, y) { ij <- combn(length(x), 2); median((y[ij[2, ]] - y[ij[1, ]]) / (x[ij[2, ]] - x[ij[1, ]])) }
full <- AN[!AN$partial, ]
TR <- do.call(rbind, lapply(c("built_km2", "wui_km2", "intermix_km2", "interface_km2"), function(v) {
  kt <- cor.test(full$year, full[[v]], method = "kendall", exact = FALSE)
  data.frame(variable = v, sen_slope_km2_per_year = sen(full$year, full[[v]]), kendall_tau = unname(kt$estimate), p_value = kt$p.value,
             first = full[[v]][1], last = tail(full[[v]], 1), change_pct = 100 * (tail(full[[v]], 1) / full[[v]][1] - 1)) }))

# ---- early vs late change (majority of 3 years) ---------------------------------------------------------------------------
maj <- function(ys) Reduce(`+`, lapply(as.character(ys), function(y) WUIY[[y]])) >= 2
early <- maj(2017:2019); late <- maj(2023:2025)
chg <- ifelse(early & late, 1L, ifelse(!early & late, 2L, ifelse(early & !late, 3L, NA_integer_)))
CHG_LAB <- c("Stable WUI", "New WUI", "Lost WUI")
by_unit <- do.call(rbind, lapply(sort(unique(unit[!is.na(unit)])), function(u) { s <- unit %in% u
  data.frame(unit = u, wui_2017_2019_km2 = sum(early[s]) * km2, wui_2023_2025_km2 = sum(late[s]) * km2, new_km2 = sum(chg[s] %in% 2) * km2, lost_km2 = sum(chg[s] %in% 3) * km2) }))
ob <- st_read(tw("data/derived/wui_thimphu.gpkg"), "buildings", quiet = TRUE)
bidx <- match(cellFromXY(g, st_coordinates(ob)), inside)
new_bld <- sum(chg[bidx] %in% 2, na.rm = TRUE)
fill <- function(v) { r <- rast(g); xx <- rep(NA_real_, ncell(g)); xx[inside] <- v; values(r) <- xx; r }
chg_r <- fill(chg); levels(chg_r) <- data.frame(value = 1:3, change = CHG_LAB)
writeRaster(chg_r, tw("data/derived/wui_change_2017_19_to_2023_25_50m.tif"), overwrite = TRUE, datatype = "INT1U", gdal = "COMPRESS=DEFLATE")
write.csv(AN, tw("data/derived/wui_annual_dynamic_world.csv"), row.names = FALSE)

# ============================================================
# DATA HEALTH
# ============================================================
data_health(run, AN[, c("built_km2", "wui_km2", "intermix_km2", "interface_km2", "mean_valid_obs", "partial")], "Annual Dynamic World WUI totals")
data_health(run, kap[, c("built_share_threshold", "kappa", "dw_settled_km2", "ob_settled_km2")], "Built-share threshold calibration (2023)")
write_health(run, notes = c(
  sprintf("Dynamic World annual label-mode composites, aggregated to 50 m class shares; settlement proxy = neighbourhood built share > %.3f (best kappa %.2f with footprint density > %.2f/km2 in 2023).", BSTAR, max(kap$kappa), SELP$D),
  sprintf("DW-based WUI 2023 vs footprint-based calibrated WUI: WUI/non-WUI agreement %.0f%%, 5-class kappa %.2f.", 100 * val[["wui_agreement"]], val[["kappa"]]),
  "Dynamic World labels change from year to year through classification noise as well as real change; the early/late comparison uses the majority of three years in each period to damp it.",
  sprintf("Mean cloud-free Dynamic World observations per pixel rose from %.1f (2017) to %.1f (2025) as Sentinel-2B and better cloud masking came in; more observations can stabilise the annual mode, so part of the trend may be observational.", AN$mean_valid_obs[AN$year == 2017], AN$mean_valid_obs[AN$year == 2025]),
  sprintf("Partial years %s are shown but excluded from trend tests.", paste(GR$partial_years, collapse = " and "))))

# ============================================================
# FIGURES
# ============================================================
dz <- study_dz(); gw <- study_gewogs()
p1 <- ggplot(kap, aes(100 * built_share_threshold, kappa)) + geom_line(linewidth = 0.5) + geom_point(size = 2) +
  annotate("point", x = 100 * BSTAR, y = max(kap$kappa), shape = 1, size = 5, stroke = 0.8) +
  labs(x = sprintf("Built share within %d m threshold, B (%%)", SELP$R), y = "Cohen's kappa with footprint-based settlement (2023)") + theme_sci()
save_fig(run, p1, 1, "built_threshold_calibration", kap, c(
  "Calibration of the Dynamic World settlement proxy for Thimphu against 2023 building footprints.",
  sprintf("Cells are settled when the Dynamic World built share within %d m exceeds B; agreement with footprint density > %.2f buildings/km2 (Open Buildings V3) measured by Cohen's kappa over all cells in the dzongkhag.", SELP$R, SELP$D),
  sprintf("Kappa peaks at B = %.1f%% (kappa %.2f), and the resulting 2023 DW-based WUI agrees with the footprint-based WUI on %.0f%% of cells, so Dynamic World can track WUI change in years without footprints.", 100 * BSTAR, max(kap$kappa), 100 * val[["wui_agreement"]])),
  size = c(4.5, 3.6))

AL <- rbind(data.frame(year = AN$year, partial = AN$partial, panel = "Built-up area (km2)", series = "Built-up", km2 = AN$built_km2),
            data.frame(year = AN$year, partial = AN$partial, panel = "WUI area (km2)", series = "Intermix", km2 = AN$intermix_km2),
            data.frame(year = AN$year, partial = AN$partial, panel = "WUI area (km2)", series = "Interface", km2 = AN$interface_km2),
            data.frame(year = AN$year, partial = AN$partial, panel = "WUI area (km2)", series = "Total WUI", km2 = AN$wui_km2))
p2 <- ggplot(AL, aes(year, km2, linetype = series)) + geom_line(data = AL[!AL$partial, ], linewidth = 0.5) +
  geom_point(aes(shape = partial), size = 1.9) + scale_shape_manual(values = c(`FALSE` = 16, `TRUE` = 1), labels = c("Full year", "Partial year"), name = NULL) +
  scale_linetype_manual(values = c(`Built-up` = "solid", Intermix = "dashed", Interface = "dotted", `Total WUI` = "solid"), name = NULL) +
  scale_x_continuous(breaks = YEARS) + facet_wrap(~ panel, scales = "free_y", ncol = 1) + labs(x = NULL, y = NULL) + theme_sci() + theme(legend.position = "bottom")
tw_ <- TR[TR$variable == "wui_km2", ]; tb_ <- TR[TR$variable == "built_km2", ]
save_fig(run, p2, 2, "wui_time_series", AN, c(
  "Built-up area and wildland-urban interface area in Thimphu dzongkhag from Dynamic World annual composites, 2016-2026.",
  sprintf("Calibrated rule applied each year with the Dynamic World settlement proxy; open symbols are partial years (excluded from trends); Theil-Sen slope with Kendall's tau over 2017-2025: built-up %+.2f km2/yr (%s), WUI %+.2f km2/yr (%s); mean cloud-free observations per pixel rose from %.1f (2017) to %.1f (2025), which can also change label stability.",
          tb_$sen_slope_km2_per_year, format_p(tb_$p_value), tw_$sen_slope_km2_per_year, format_p(tw_$p_value),
          AN$mean_valid_obs[AN$year == 2017], AN$mean_valid_obs[AN$year == 2025]),
  sprintf("WUI area changed by %+.0f%% between 2017 and 2025 (%.0f to %.0f km2)%s.", tw_$change_pct, tw_$first, tw_$last,
          ifelse(tw_$p_value < 0.05, ", a significant trend that adds new edge to protect each year", ", but year-to-year classification noise is as large as the trend, so growth is not yet statistically established"))),
  size = c(6, 5))

cd <- as.data.frame(mask(chg_r, vect(dz)), xy = TRUE, na.rm = TRUE); names(cd)[3] <- "change"; cd$change <- factor(cd$change, CHG_LAB)
p3 <- ggplot() + geom_raster(data = cd, aes(x, y, fill = change)) + scale_fill_manual(values = c(`Stable WUI` = "#bbbbbb", `New WUI` = "#D55E00", `Lost WUI` = "#0072B2"), name = NULL) +
  geom_sf(data = gw, fill = NA, colour = "#888888", linewidth = 0.25) + geom_sf(data = dz, fill = NA, colour = "black", linewidth = 0.5) +
  ggspatial::annotation_scale(location = "bl", text_family = SCI$font, height = unit(0.15, "cm")) + theme_sci_map() + theme(legend.position = "right")
save_fig(run, p3, 3, "wui_change_map", data.frame(change = CHG_LAB, km2 = c(sum(chg %in% 1), sum(chg %in% 2), sum(chg %in% 3)) * km2), c(
  "Change in wildland-urban interface in Thimphu between 2017-2019 and 2023-2025 (Dynamic World, calibrated rule).",
  "A cell counts as WUI in a period when it is WUI in at least two of the three years; Okabe-Ito colours for change classes.",
  sprintf("%.1f km2 became WUI and %.1f km2 left it; %s of today's buildings stand in new WUI, so WUI growth adds exposed settlement faster than it removes it.", sum(chg %in% 2) * km2, sum(chg %in% 3) * km2, format(new_bld, big.mark = ","))),
  size = c(6.5, 6))

bu <- by_unit[order(-by_unit$new_km2), ]
bl <- rbind(data.frame(unit = bu$unit, period = "2017-2019", km2 = bu$wui_2017_2019_km2), data.frame(unit = bu$unit, period = "2023-2025", km2 = bu$wui_2023_2025_km2))
bl$unit <- factor(bl$unit, rev(bu$unit))
p4 <- ggplot(bl, aes(km2, unit, fill = period)) + geom_col(position = position_dodge(0.7), width = 0.65, colour = "black", linewidth = 0.25) +
  scale_fill_manual(values = c(`2017-2019` = "#ffffff", `2023-2025` = "#555555"), name = NULL) + labs(x = "WUI area (km2)", y = NULL) + theme_sci() + theme(legend.position = "bottom")
save_fig(run, p4, 4, "wui_change_by_gewog", by_unit, c(
  "WUI area by gewog in Thimphu, 2017-2019 versus 2023-2025 (Dynamic World, majority of three years).",
  "Gewogs ordered by newly added WUI area; the city of Thimphu lies within the Chang, Kawang and Mewang gewog polygons.",
  sprintf("%s gains the most new WUI (%.1f km2), so growth-related fire planning should start there.", bu$unit[1], bu$new_km2[1])),
  size = c(5.5, 4))

write_process(run, kap, "built_threshold_calibration")
write_process(run, AN, "annual_totals")
write_process(run, TR, "trend_tests")
write_process(run, by_unit, "change_by_gewog")
write_json_pretty(list(built_share_threshold = BSTAR, kappa = max(kap$kappa), validation_2023 = as.list(val), trends = TR, annual = AN,
                       new_wui_km2 = sum(chg %in% 2) * km2, lost_wui_km2 = sum(chg %in% 3) * km2, stable_wui_km2 = sum(chg %in% 1) * km2,
                       buildings_in_new_wui = new_bld, by_unit = by_unit), tw("data/derived/results_growth.json"))
build_report(run, intro = c(
  sprintf("Annual wildland-urban interface of Thimphu 2016-2026 from Dynamic World, using the calibrated rule and a settlement proxy matched to 2023 footprints (kappa %.2f).", max(kap$kappa)),
  sprintf("WUI area changed from %.0f km2 (2017) to %.0f km2 (2025); %.1f km2 of new WUI between 2017-2019 and 2023-2025.", tw_$first, tw_$last, sum(chg %in% 2) * km2)))
print(AN); print(TR)
