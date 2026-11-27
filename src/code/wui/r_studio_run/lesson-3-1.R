# Lesson 3.1 | How far is each building from past fire?
# Run the setup first, then select the calculation or click Source for the whole file.
# Numerical examples describe the workshop dataset and settings.

# Load project helpers and the packaged inputs used below.
source("r_studio_run/00_setup.R", local = TRUE)

B <- B03()
say("Buildings inside Thimphu: %s", format(length(B$dist), big.mark = ","))
print(round(quantile(B$dist, c(0, .1, .25, .5, .75, .9, 1))))
for (d in c(500, 1000, 2000)) say("Share of buildings with fire evidence within %4d m: %.1f%%", d, 100 * mean(B$dist <= d))
print(round(tapply(B$fire, B$unit, mean), 2))

