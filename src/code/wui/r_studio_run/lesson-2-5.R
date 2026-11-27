# Lesson 2.5 | Classify cells into the five WUI classes
# Run the setup first, then select the calculation or click Source for the whole file.
# Numerical examples describe the workshop dataset and settings.

# Load project helpers and the packaged inputs used below.
# Block 01: Open the shared lesson setup ----
lesson_setup <- "thimphu_WUI/r_studio_run/00_setup.R"
if (!file.exists(lesson_setup)) lesson_setup <- "r_studio_run/00_setup.R"
source(lesson_setup, local = TRUE)

# Block 02: Run the short exercise and read its output ----

hr("Five hand examples (D=20, V=50%, P=100 m)")
ex <- data.frame(cell = LETTERS[1:5], density = c(30, 30, 30, 5, 5), veg_pct = c(65, 20, 20, 70, 20), patch_m = c(80, 80, 300, 80, 80))
ex$class <- CLASSES[classify_wui(ex$density, ex$veg_pct, ex$patch_m, 20, 50, 100)]
print(ex)
hr("The whole city window under two rules")
g <- crop(grid50(), window()); cr <- function(f, lyr) values(crop(rast(file.path(LAY, f))[[lyr]], g), mat = FALSE)
rules <- list(`US baseline` = CFG$baseline, `Fire-selected` = list(D = 20, V = 50, P = 100, R = 1000, A = 5, veg = "wc_woody_grass"))
maps <- list()
for (nm in names(rules)) { x <- rules[[nm]]
  cl <- classify_wui(cr("density_ob.tif", paste0("r", x$R)), cr(sprintf("vegpct_%s.tif", x$veg), paste0("r", x$R)),
                     cr(sprintf("patchdist_%s.tif", x$veg), paste0("a", x$A)), x$D, x$V, x$P)
  say("%-14s %s", nm, paste(sprintf("%s %.1f km2", CLASSES, tabulate(cl, 5) * km2), collapse = " | "))
  r <- rast(g); values(r) <- cl; maps[[nm]] <- r }
f <- png_out("2.5_classes"); par(mfrow = c(1, 2), oma = c(3, 0, 0, 0))
for (nm in names(maps)) plot(classify(maps[[nm]], cbind(1:5, 1:5)), col = unname(WUI_COLS), breaks = 0.5:5.5, main = nm, legend = FALSE)
par(fig = c(0, 1, 0, 1), oma = c(0, 0, 0, 0), mar = c(0, 0, 0, 0), new = TRUE); plot.new()
legend("bottom", CLASSES, fill = unname(WUI_COLS), horiz = TRUE, bty = "n", cex = 0.8)
dev.off(); say("Picture: %s", f)

