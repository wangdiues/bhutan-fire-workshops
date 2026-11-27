# 03  Post-fire SPECTRAL trajectories of mapped burned patches, Paro and Thimphu (v1.1)
# v1.1 (reviewer comments R2-4, R3-3/4/5): trajectories are spectral (NBR), not ecological recovery; the v1.0 recovery
# percentage is dropped; unequal follow-up and repeated observations are handled with a linear mixed model.
#   rel(i, t) = [NBR_patch(i, t) - NBR_ring(i, t)] - [NBR_patch(i, pre) - NBR_ring(i, pre)]
# where NBR is the annual Landsat median (full year, monsoon included), patch = all mapped patches of incident i,
# ring = median of a 2-5 km ring excluding all patches + 100 m, pre = last calendar year before the fire,
# t = years since fire (0 = first annual composite mostly after the fire: fire year if January-June, else next year).
# Models (lme4): rel ~ factor(t) + (1 | incident), and rel ~ factor(t) * class + (1 | incident) for incidents
# dominated by moderate vs high spectral change; estimated marginal means (emmeans) with Holm-adjusted tests.
# Checks: reference-ring stability, follow-up per year, balanced subset (incidents with >= 3 post-fire years).
# Run: Rscript thimphu_paro_burn_severity/scripts/03_post_fire_recovery.R   (after 02)
source(if (file.exists("thimphu_paro_burn_severity/R/tp_common.R")) "thimphu_paro_burn_severity/R/tp_common.R" else "R/tp_common.R")
source(tp("R/sci_figure.R"))
suppressPackageStartupMessages({ library(exactextractr); library(lme4); library(emmeans); library(patchwork) })
set.seed(20261124)
# ============================================================
# CONFIGURATION
# ============================================================
RC <- CFG$recovery
SLUG <- "02-recovery"
TITLE <- "Post-fire spectral trajectories of mapped burned patches, Paro and Thimphu"
GP <- tp("data/derived/burn_severity_paro_thimphu.gpkg"); LS <- tp("data/raw/landsat_annual_nbr")
YEARS <- 2012:2025; MIN_N <- RC$min_patches_per_point; BAL_MIN_POST <- 3; FLAT <- 0.02
# ============================================================
unlink(file.path(SCI_OUT_ROOT, SLUG), recursive = TRUE)
run <- sci_run(SLUG, TITLE, inputs = c(GP, file.path(LS, "x")))
pat <- st_read(GP, "burned_patches_selected", quiet = TRUE); ip <- st_read(GP, "incident_points", quiet = TRUE); ip <- ip[ip$map_status == "Mapped", ]
nbr <- rast(lapply(YEARS, function(y) { r <- rast(file.path(LS, sprintf("landsat_nbr_%d.tif", y))); v <- r[["nbr_x10000"]] / 1e4; v[r[["valid_observations"]] < 1] <- NA; names(v) <- y; v }))
excl <- st_union(st_buffer(pat, 100))

rows <- list()
for (e in unique(pat$event_id)) {
  pe <- pat[pat$event_id == e, ]; pt <- ip[ip$event_id == e, ]
  fd <- as.Date(pe$fire_date[1]); y <- as.integer(format(fd, "%Y")); t0 <- if (as.integer(format(fd, "%m")) <= 6) y else y + 1
  ring <- st_difference(st_difference(st_buffer(pt, 5000), st_buffer(pt, 2000)), excl)
  pv <- as.numeric(exact_extract(nbr, st_sf(geometry = st_union(pe)), "mean", progress = FALSE))
  rv <- as.numeric(exact_extract(nbr, ring, "median", progress = FALSE))
  d <- data.frame(event_id = e, year = YEARS, patch_nbr = pv, ring_nbr = rv); d$diff <- d$patch_nbr - d$ring_nbr
  pre <- d$diff[d$year == t0 - 1]; ring_pre <- d$ring_nbr[d$year == t0 - 1]
  if (!length(pre) || !is.finite(pre)) next
  d$rel <- d$diff - pre; d$ring_rel <- d$ring_nbr - ring_pre; d$t <- d$year - t0
  cls <- c("Low", "Moderate", "High")[which.max(c(sum(pe$low_ha), sum(pe$moderate_ha), sum(pe$high_ha)))]
  d$class <- cls; d$area_ha <- sum(pe$area_ha); d$fire_date <- as.character(fd); d$post_years <- max(YEARS) - t0
  rows[[e]] <- d
}
D <- do.call(rbind, rows); D <- D[is.finite(D$rel) & D$t >= -RC$years_before & D$t <= RC$years_after, ]
if (length(unique(D$event_id)) < max(2, MIN_N)) {   # e.g. after a workshop quick run of step 02 that mapped too few fires
  message(sprintf("Only %d mapped incident(s) with trajectories: the mixed models need at least %d. Run step 02 in full (without -Quick) first. Step 03 stopped; nothing else written.",
                  length(unique(D$event_id)), max(2, MIN_N))); quit(save = "no", status = 0) }
FU <- aggregate(event_id ~ t, D, function(x) length(unique(x))); names(FU)[2] <- "incidents"
TS <- FU$t[FU$incidents >= MIN_N & FU$t != -1]
Dm <- D[D$t %in% c(-1, TS), ]; Dm$tf <- relevel(factor(Dm$t), ref = "-1")

# ---- model 1: trajectory --------------------------------------------------------------------------------------------------------
m1 <- lmer(rel ~ tf + (1 | event_id), data = Dm, REML = TRUE)
em1 <- as.data.frame(summary(emmeans(m1, ~ tf), infer = c(TRUE, FALSE)))
ct1 <- as.data.frame(summary(contrast(emmeans(m1, ~ tf), "trt.vs.ctrl", ref = 1), adjust = "holm", infer = c(TRUE, TRUE)))
em1$t <- as.integer(as.character(em1$tf)); ct1$t <- as.integer(levels(Dm$tf)[-1])   # trt.vs.ctrl rows follow the non-reference levels
# balanced subset: incidents with at least BAL_MIN_POST post-fire years, years 0..BAL_MIN_POST-1
bal_ids <- unique(D$event_id[D$post_years >= BAL_MIN_POST])
Db <- D[D$event_id %in% bal_ids & D$t %in% c(-1, 0:(BAL_MIN_POST - 1)), ]; Db$tf <- relevel(factor(Db$t), ref = "-1")
mb <- if (length(bal_ids) >= MIN_N) lmer(rel ~ tf + (1 | event_id), data = Db) else NULL
emb <- if (!is.null(mb)) { x <- as.data.frame(summary(emmeans(mb, ~ tf), infer = c(TRUE, FALSE))); x$t <- as.integer(as.character(x$tf)); x } else NULL

# ---- model 2: by dominant spectral-change class (moderate vs high) -------------------------------------------------------------------
Dg <- Dm[Dm$class %in% c("Moderate", "High") & Dm$t %in% c(-1, TS[TS <= 3]), ]; Dg$class <- factor(Dg$class, c("Moderate", "High"))
ng <- tapply(Dg$event_id, Dg$class, function(x) length(unique(x)))
m2 <- if (all(ng >= 3)) lmer(rel ~ tf * class + (1 | event_id), data = droplevels(Dg)) else NULL
em2 <- if (!is.null(m2)) { x <- as.data.frame(summary(emmeans(m2, ~ class | tf), infer = c(TRUE, FALSE))); x$t <- as.integer(as.character(x$tf)); x } else NULL
ct2 <- if (!is.null(m2)) as.data.frame(summary(contrast(emmeans(m2, ~ class | tf), "revpairwise"), adjust = "holm", by = NULL, infer = c(TRUE, TRUE))) else NULL

# ---- checks -------------------------------------------------------------------------------------------------------------------------
RS <- do.call(rbind, lapply(split(D[D$t %in% c(-1, TS), ], D$t[D$t %in% c(-1, TS)]), function(d) { m <- mean(d$ring_rel, na.rm = TRUE); s <- sd(d$ring_rel, na.rm = TRUE) / sqrt(sum(is.finite(d$ring_rel)))
  data.frame(t = d$t[1], ring_change = m, low = m - 1.96 * s, high = m + 1.96 * s, n = nrow(d)) }))
INC <- do.call(rbind, lapply(split(D, D$event_id), function(d) { p <- d[d$t >= 0, ]; r0 <- p$rel[p$t == 0]; rl <- tail(p$rel, 1)
  data.frame(event_id = d$event_id[1], fire_date = d$fire_date[1], dominant_class = d$class[1], area_ha = d$area_ha[1], post_years_observed = nrow(p),
             change_year0 = if (length(r0)) r0 else NA, latest_year = if (nrow(p)) max(p$year) else NA, change_latest = if (nrow(p)) rl else NA,
             initial_change_type = if (!length(r0)) "no year-0 value" else if (r0 < -FLAT) "decline" else if (r0 > FLAT) "increase" else "flat (|change| <= 0.02)",
             within_0.02_of_prefire_at_latest = if (nrow(p)) abs(rl) <= FLAT else NA) }))
write.csv(INC, tp("data/derived/incident_spectral_trajectory_summary.csv"), row.names = FALSE)

# ============================================================
# DATA HEALTH
# ============================================================
data_health(run, D[, c("t", "patch_nbr", "ring_nbr", "rel", "ring_rel", "class")], "Incident-year spectral trajectories")
data_health(run, INC[, c("dominant_class", "area_ha", "post_years_observed", "change_year0", "change_latest", "initial_change_type")], "Incident summaries")
write_health(run, notes = c(
  sprintf("%d mapped incidents with a pre-fire annual composite; follow-up ranges from %d to %d post-fire years (incidents per year in process data).", length(unique(D$event_id)), min(INC$post_years_observed), max(INC$post_years_observed)),
  "Annual Landsat composites are full-year medians that mix seasons; the trajectories describe spectral change only and say nothing directly about canopy mortality, regeneration or structure.",
  "Repeated observations per incident are handled with an incident random intercept; tests against the pre-fire year are Holm-adjusted.",
  "The v1.0 'recovery percentage' is not reported: it is unstable when the year-0 change is near zero and values above 100% do not mean restoration beyond the pre-fire state."))

# ============================================================
# FIGURES
# ============================================================
p1 <- ggplot() + geom_hline(yintercept = 0, linetype = "dashed") +
  geom_line(data = D, aes(t, rel, group = event_id), colour = "#cccccc", linewidth = 0.3) +
  geom_ribbon(data = em1, aes(t, ymin = lower.CL, ymax = upper.CL), fill = "#888888", alpha = 0.35) +
  geom_line(data = em1, aes(t, emmean), linewidth = 0.7) + geom_point(data = em1, aes(t, emmean), size = 1.8) +
  { if (!is.null(emb)) geom_point(data = emb, aes(t + 0.15, emmean), shape = 1, size = 2) } +
  scale_x_continuous(breaks = -RC$years_before:RC$years_after) + labs(x = "Years since fire (0 = first post-fire annual composite)", y = "Change in patch-minus-ring NBR from pre-fire year") + theme_sci()
y0 <- ct1[ct1$t == 0, ]; last_t <- max(TS); yl <- ct1[ct1$t == last_t, ]
save_fig(run, p1, 1, "spectral_trajectory", merge(em1, FU, by = "t"), c(
  sprintf("Post-fire spectral trajectories of mapped burned patches relative to their 2-5 km reference rings, Paro and Thimphu (%d incidents, annual Landsat NBR 2012-2025).", length(unique(D$event_id))),
  sprintf("Grey lines: incidents; black line and band: estimated marginal means with 95%% CI from a linear mixed model with incident random intercept, years with >= %d incidents; open circles: balanced subset of %d incidents with >= %d post-fire years; Holm-adjusted tests against the pre-fire year in process data.",
          MIN_N, length(bal_ids), BAL_MIN_POST),
  sprintf("Relative NBR falls by %.3f in the first post-fire year (Holm %s) and is still %.3f below the pre-fire level in year %d (Holm %s, %d incidents), so the spectral signal of these fires persists for several years; whether canopy or understorey have recovered cannot be judged from NBR alone.",
          abs(y0$estimate), format_p(y0$p.value), abs(yl$estimate), last_t, format_p(yl$p.value), FU$incidents[FU$t == last_t])), size = c(6, 4))

if (!is.null(em2)) {
  p2 <- ggplot(em2, aes(t, emmean, shape = class, linetype = class)) + geom_hline(yintercept = 0, linetype = "dashed", colour = "#888888") +
    geom_errorbar(aes(ymin = lower.CL, ymax = upper.CL), width = 0.15, linewidth = 0.35, position = position_dodge(0.3)) +
    geom_line(linewidth = 0.6, position = position_dodge(0.3)) + geom_point(size = 2, position = position_dodge(0.3)) +
    scale_shape_manual(values = c(Moderate = 1, High = 16), name = "Dominant spectral-change class") + scale_linetype_manual(values = c(Moderate = "dashed", High = "solid"), name = "Dominant spectral-change class") +
    scale_x_continuous(breaks = -1:3) + labs(x = "Years since fire", y = "Change in patch-minus-ring NBR (EMM, 95% CI)") + theme_sci() + theme(legend.position = "bottom")
  c0 <- ct2[ct2$tf == "0", ]
  save_fig(run, p2, 2, "trajectory_by_class", em2, c(
    sprintf("Spectral trajectories of incidents dominated by moderate (n = %d) or high (n = %d) spectral change, Paro and Thimphu.", ng[["Moderate"]], ng[["High"]]),
    "Estimated marginal means and 95% CI from a linear mixed model with year x class interaction and incident random intercept; Holm-adjusted high-minus-moderate contrasts per year in process data.",
    sprintf("In the first post-fire year high-change incidents fall %.3f further than moderate ones (Holm %s); because RBR and the annual NBR share the same spectral basis, this shows temporal consistency of the spectral signal, not independent confirmation of ecological severity.",
            abs(c0$estimate), format_p(c0$p.value))), size = c(6, 4))
}

pa <- ggplot(RS, aes(t, ring_change)) + geom_hline(yintercept = 0, linetype = "dashed") + geom_errorbar(aes(ymin = low, ymax = high), width = 0.15, linewidth = 0.35) + geom_point(size = 1.8) +
  scale_x_continuous(breaks = RS$t) + labs(x = "Years since fire", y = "Reference-ring NBR change from pre-fire year") + theme_sci()
pb <- ggplot(FU, aes(t, incidents)) + geom_col(fill = "#bbbbbb", colour = "black", linewidth = 0.25, width = 0.7) + geom_hline(yintercept = MIN_N, linetype = "dashed") +
  scale_x_continuous(breaks = FU$t) + labs(x = "Years since fire", y = "Incidents contributing (count)") + theme_sci()
p3 <- pa + pb + plot_annotation(tag_levels = "a", tag_prefix = "(", tag_suffix = ")") & theme(plot.tag = element_text(family = SCI$font, size = 10))
save_fig(run, p3, 3, "reference_and_followup", merge(RS, FU, by = "t", all = TRUE), c(
  "Checks on the trajectory analysis: (a) NBR change of the reference rings themselves; (b) number of incidents contributing in each year since fire.",
  sprintf("(a) mean and 95%% CI of ring NBR change from the pre-fire year; (b) dashed line: minimum of %d incidents for a year to enter the model.", MIN_N),
  sprintf("Ring NBR changes by at most %.3f in any year, small against the %.3f patch decline, so the reference is stable; follow-up falls from %d incidents in year 0 to %d in year %d, which is why the mixed model, not raw yearly means, is used.",
          max(abs(RS$ring_change)), abs(y0$estimate), FU$incidents[FU$t == 0], FU$incidents[FU$t == last_t], last_t)), size = c(7.2, 3.6))

write_process(run, INC, "incident_summary")
write_process(run, D, "incident_year_trajectory")
write_process(run, em1, "emm_trajectory"); write_process(run, ct1, "tests_vs_prefire_holm")
if (!is.null(em2)) { write_process(run, em2, "emm_by_class"); write_process(run, ct2, "high_minus_moderate_holm") }
write_process(run, FU, "followup_by_year"); write_process(run, RS, "reference_ring_stability")
write_json_pretty(list(n_incidents = length(unique(D$event_id)), years_modelled = TS, followup = FU, emm = em1, tests = ct1, balanced_n = length(bal_ids), emm_balanced = emb,
                       class_n = as.list(ng), emm_class = em2, class_tests = ct2, ring = RS, drop_year0 = y0$estimate, drop_year0_p = y0$p.value,
                       last_year = last_t, change_last = yl$estimate, change_last_p = yl$p.value, flat_initial = sum(INC$initial_change_type != "decline"),
                       within_0.02_latest = sum(INC$within_0.02_of_prefire_at_latest, na.rm = TRUE)), tp("data/derived/results_recovery.json"))
build_report(run, intro = c(
  sprintf("Post-fire spectral trajectories (annual Landsat NBR, patch minus reference ring) of %d mapped incidents in Paro and Thimphu, modelled with incident random effects.", length(unique(D$event_id))),
  "These are spectral trajectories, not measurements of ecological recovery; the class comparison shows temporal consistency of the spectral signal, not independent validation of severity."))
print(em1); print(ct1)
