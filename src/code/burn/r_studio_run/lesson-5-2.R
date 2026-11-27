# Lesson 5.2 | Accuracy sample: inclusion probabilities and error-adjusted area (worked example)
# Run the setup first, then select the calculation or click Source for the whole file.
# Numerical examples describe the workshop dataset and settings.

# Load project helpers and the packaged inputs used below.
# Block 01: Open the shared lesson setup ----
lesson_setup <- "thimphu_paro_burn_severity/r_studio_run/00_setup.R"
if (!file.exists(lesson_setup)) lesson_setup <- "r_studio_run/00_setup.R"
source(lesson_setup, local = TRUE)

# Block 02: Run the short exercise and read its output ----

B <- read.csv(file.path(DER, "field_plan", "B_accuracy_sample.csv"))
t <- aggregate(cbind(points = 1, inclusion_probability, stratum_area_ha) ~ stratum, B, function(x) c(sum = sum(x), first = x[1]))
t <- data.frame(stratum = t$stratum, points = t$points[, "sum"], inclusion_probability = signif(t$inclusion_probability[, "first"], 3), mapped_ha = round(t$stratum_area_ha[, "first"]))
t <- t[order(factor(t$stratum, SEV_LEVELS)), ]; print(t, row.names = FALSE)
hr("Worked example with an invented field result (Olofsson et al. 2014)")
W <- t$mapped_ha / sum(t$mapped_ha); names(W) <- SEV_SHORT
cm <- matrix(c(44, 5, 1, 0,  8, 34, 7, 1,  1, 7, 36, 6,  0, 1, 8, 41), 4, byrow = TRUE, dimnames = list(map = names(W), field = names(W)))
say("Invented counts: rows = mapped class of 50 points each, columns = class found in the field"); print(cm)
p <- W * cm / rowSums(cm)
say("Overall accuracy = %.2f", sum(diag(p)))
print(data.frame(class = names(W), users_accuracy = round(diag(cm) / rowSums(cm), 2), producers_accuracy = round(diag(p) / colSums(p), 2),
                 mapped_ha = round(t$mapped_ha), error_adjusted_ha = round(colSums(p) * sum(t$mapped_ha))), row.names = FALSE)
say("Error-adjusted area uses the field result to correct the mapped area of each class.")

