# Lesson 3.4 | Leave-one-gewog-out: is the choice stable? (P only)
# Run the setup first, then select the calculation or click Source for the whole file.
# Numerical examples describe the workshop dataset and settings.

# Load project helpers and the packaged inputs used below.
source("r_studio_run/00_setup.R", local = TRUE)

B <- B03(); Ps <- CFG$sensitivity_grid$P
W <- sapply(Ps, function(p) { x <- SELR; x$P <- p; rule_wui(B, x) })
for (u in sort(unique(B$unit))) { tr <- B$unit != u
  jt <- apply(W[tr, ], 2, function(w) cm(w, B$fire[tr])[["J"]]); best <- which.max(round(jt, 6))
  say("Leave out %-22s -> best P on the other units = %4d m | J on the left-out unit = %6.3f (%s buildings)",
      u, Ps[best], cm(W[!tr, best], B$fire[!tr])[["J"]], format(sum(!tr), big.mark = ",")) }
say("\nThe full step 03 does this for all 2,160 rules at once; its pooled out-of-fold J is in results_calibration.json (cv_J).")

