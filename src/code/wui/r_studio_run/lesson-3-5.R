# Lesson 3.5 | Bootstrap by gewog: how uncertain is J?
# Run the setup first, then select the calculation or click Source for the whole file.
# Numerical examples describe the workshop dataset and settings.

# Load project helpers and the packaged inputs used below.
# Block 01: Open the shared lesson setup ----
lesson_setup <- "thimphu_WUI/r_studio_run/00_setup.R"
if (!file.exists(lesson_setup)) lesson_setup <- "r_studio_run/00_setup.R"
source(lesson_setup, local = TRUE)

# Block 02: Run the short exercise and read its output ----

B <- B03(); wsel <- rule_wui(B, SELR); wbase <- rule_wui(B, CFG$baseline); units <- unique(B$unit)
bt <- t(replicate(300, { us <- sample(units, length(units), replace = TRUE); ix <- unlist(lapply(us, function(u) which(B$unit == u)))
  c(selected = cm(wsel[ix], B$fire[ix])[["J"]], baseline = cm(wbase[ix], B$fire[ix])[["J"]]) }))
print(round(apply(bt, 2, quantile, c(.025, .5, .975), na.rm = TRUE), 3))
say("300 replicates here (step 03 uses 1,000). Wide intervals = few independent units.")

