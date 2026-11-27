# Lesson 3.2 | Detection by fire size and thermal evidence (Wilson intervals, logistic model)
# Run the setup first, then select the calculation or click Source for the whole file.
# Numerical examples describe the workshop dataset and settings.

# Load project helpers and the packaged inputs used below.
source("r_studio_run/00_setup.R", local = TRUE)

M <- read.csv(file.path(DER, "incident_sensor_metrics.csv")); M$size <- cut(M$reported_area_ha, c(0, 1, 10, Inf), right = FALSE, labels = c("< 1 ha", "1-10 ha", ">= 10 ha"))
for (grp in list(c("size", "size"), c("thermal_evidence", "thermal evidence"), c("sensor", "sensor"))) {
  hr(paste("Detection by", grp[2]))
  t <- do.call(rbind, lapply(split(M, M[[grp[1]]]), function(d) { ci <- wilson_ci(sum(d$detected), nrow(d))
    data.frame(group = as.character(d[[grp[1]]][1]), pairs = nrow(d), detected = sum(d$detected), rate_pct = round(100 * mean(d$detected)), ci_low = round(100 * ci[1]), ci_high = round(100 * ci[2])) }))
  print(t, row.names = FALSE) }
hr("Logistic regression: detected ~ log10(reported area) + sensor")
fit <- glm(detected ~ log10(reported_area_ha) + sensor, family = binomial, data = M[M$reported_area_ha > 0, ])
print(round(cbind(estimate = coef(fit), odds_ratio = exp(coef(fit))), 3))
say("Odds ratio for log10(area): each tenfold larger fire multiplies the odds of detection by %.1f", exp(coef(fit)[2]))

