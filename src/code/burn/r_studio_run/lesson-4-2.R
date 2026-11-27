# Lesson 4.2 | Why a mixed model? (all incidents)
# Run the setup first, then select the calculation or click Source for the whole file.
# Numerical examples describe the workshop dataset and settings.

# Load project helpers and the packaged inputs used below.
source("r_studio_run/00_setup.R", local = TRUE)

tr <- openxlsx::read.xlsx(tp("outputs/02-recovery/process_data/02_incident_year_trajectory.xlsx"))
tr <- tr[tr$t >= -1 & tr$t <= 4, ]
say("Incidents contributing to each year since fire:"); print(table(t = tr$t))
m0 <- aggregate(rel ~ t, tr, mean); names(m0)[2] <- "simple_mean"
fit <- suppressMessages(lme4::lmer(rel ~ factor(t) + (1 | event_id), data = transform(tr, t = relevel(factor(t), ref = "-1"))))
em <- as.data.frame(emmeans::emmeans(fit, ~ t)); m0$model_mean <- em$emmean[match(m0$t, em$t)]
print(transform(m0, simple_mean = round(simple_mean, 3), model_mean = round(model_mean, 3)), row.names = FALSE)
say("The model compares each fire with itself, so years with fewer (or different) fires are not biased by who happens to be in them.")
hr("Holm adjustment by hand for 5 p-values")
p <- c(0.001, 0.004, 0.012, 0.030, 0.200); print(data.frame(raw = p, holm = round(p.adjust(p, "holm"), 3), bh = round(p.adjust(p, "BH"), 3)), row.names = FALSE)

