# Synthetic exercise. Each row represents a 1 km² teaching neighbourhood.
area <- data.frame(place = c("A", "B", "C", "D"), buildings = c(28, 36, 5, 21),
                   vegetation_pct = c(60, 25, 80, 30), distance_m = c(0, 100, 50, 600))

# Compare neighbourhoods against illustrative settlement and vegetation thresholds.
settled <- area$buildings >= 20
intermix <- settled & area$vegetation_pct >= 50
interface <- settled & !intermix & area$distance_m <= 250
area$class <- ifelse(intermix, "intermix", ifelse(interface, "interface", "other"))
print(area, row.names = FALSE)
stopifnot(identical(area$class, c("intermix", "interface", "other", "other")))
