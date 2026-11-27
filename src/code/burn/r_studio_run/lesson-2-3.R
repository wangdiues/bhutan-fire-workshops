# Lesson 2.3 | Reference ring offset, dNBR_c, RBR and RdNBR
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

P <- example(); V <- P$V; near <- V$dist <= 500 & P$usable
say("Usable ring pixels (2-5 km): %s", format(sum(P$ring), big.mark = ","))
say("Ring dNBR: median %.3f (this is the offset), IQR %.3f", P$off, IQR(V$dnbr[P$ring]))
say("Inside 500 m: median dNBR %.3f -> dNBR_c %.3f | median RBR %.0f | median RdNBR %.0f", median(V$dnbr[near]), median(V$dnbr_c[near]), median(V$rbr[near]), median(V$rdnbr[near], na.rm = TRUE))
hr("RBR and RdNBR by hand for the same change (dNBR_c = 0.20)")
for (pre in c(0.60, 0.30, 0.05)) say("  pre-fire NBR %.2f: RBR = 1000 x 0.20 / (%.2f + 1.001) = %4.0f | RdNBR = 1000 x 0.20 / sqrt(%.2f) = %5.0f",
    pre, pre, idx_rbr(0.20, pre), pre, idx_rdnbr(0.20, pre))
say("RdNBR explodes as pre-fire NBR approaches 0 (sparse grass); RBR stays stable. That is why RBR is the main index.")

