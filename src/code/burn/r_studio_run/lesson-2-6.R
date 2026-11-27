# Lesson 2.6 | Independent thermal evidence for the example fire
# Run the setup first, then select the calculation or click Source for the whole file.
# Numerical examples describe the workshop dataset and settings.

# Load project helpers and the packaged inputs used below.
# Block 01: Open the shared lesson setup ----
lesson_setup <- "thimphu_paro_burn_severity/r_studio_run/00_setup.R"
if (!file.exists(lesson_setup)) lesson_setup <- "r_studio_run/00_setup.R"
source(lesson_setup, local = TRUE)

# Block 02: Run the short exercise and read its output ----
EXAMPLE <- training_example("mapping_event")
SENSOR <- training_example("mapping_sensor")
KEY <- paste(EXAMPLE, SENSOR, sep = "_")

P <- example(); fd <- as.Date(P$ev$start_date_local); c0 <- crds(P$pt)
fi <- read.csv(file.path(VD, "firms_points.csv")); fi$date <- as.Date(fi$date); mc <- read.csv(file.path(VD, "mcd64a1_burned_pixels.csv")); mc$date <- as.Date(mc$date)
near <- function(d) d$date >= fd - TH$days_before & d$date <= fd + TH$days_after & sqrt((d$x - c0[1])^2 + (d$y - c0[2])^2) <= TH$radius_m
say("Search: within %d m of the reported point, %d days before to %d days after %s", TH$radius_m, TH$days_before, TH$days_after, fd)
say("FIRMS active-fire detections: %d | MCD64A1 burned 500 m pixels: %d", sum(near(fi)), sum(near(mc)))
if (any(near(fi))) print(head(fi[near(fi), intersect(c("date", "sensor", "confidence", "frp"), names(fi))], 10), row.names = FALSE)

