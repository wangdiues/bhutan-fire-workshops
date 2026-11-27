# Lesson 3.2 | Confusion matrix and Youden J for two rules
# Run the setup first, then select the calculation or click Source for the whole file.
# Numerical examples describe the workshop dataset and settings.

# Load project helpers and the packaged inputs used below.
source("r_studio_run/00_setup.R", local = TRUE)

B <- B03()
for (nm in c("US baseline", "Fire-selected")) { x <- if (nm == "US baseline") CFG$baseline else SELR
  r <- cm(rule_wui(B, x), B$fire)
  hr(nm)
  print(matrix(c(r[["TP"]], r[["FN"]], r[["FP"]], r[["TN"]]), 2, byrow = TRUE,
               dimnames = list(c("fire within 1 km", "no fire within 1 km"), c("mapped WUI", "mapped non-WUI"))))
  say("sensitivity %.3f | specificity %.3f | Youden J %.3f", r[["sens"]], r[["spec"]], r[["J"]]) }

