# Lesson 5.1 | Calibration plots: purity of the 3 x 3 neighbourhood
# Run the setup first, then select the calculation or click Source for the whole file.
# Numerical examples describe the workshop dataset and settings.

# Load project helpers and the packaged inputs used below.
source("r_studio_run/00_setup.R", local = TRUE)
EXAMPLE <- training_example("mapping_event")
SENSOR <- training_example("mapping_sensor")
KEY <- paste(EXAMPLE, SENSOR, sep = "_")

cl <- rast(file.path(DER, "severity_rasters", paste0(KEY, "_severity.tif"))); levels(cl) <- NULL
hom <- focal(cl, 3, fun = function(x) if (is.na(x[5])) NA else sum(x == x[5], na.rm = TRUE), expand = FALSE)
d <- data.frame(cls = values(cl, mat = FALSE), hom = values(hom, mat = FALSE)); d <- d[!is.na(d$cls) & d$cls > 0, ]
need <- ifelse(d$cls == 1, CFG$field_plan$min_same_neighbours_low, CFG$field_plan$min_same_neighbours)
t <- do.call(rbind, lapply(1:3, function(k) data.frame(class = SEV_SHORT[k + 1], pixels = sum(d$cls == k), pure_enough = sum(d$cls == k & d$hom >= need), need = unique(need[d$cls == k]))))
print(t, row.names = FALSE); say("A plot centred on a 'pure' pixel is very likely to measure the class the map says (the GPS can be off by a pixel).")
A <- read.csv(file.path(DER, "field_plan", "A_calibration_plots.csv")); say("\nSample A drawn: %d plots", nrow(A)); print(table(stratum = A$stratum, role = A$role))

