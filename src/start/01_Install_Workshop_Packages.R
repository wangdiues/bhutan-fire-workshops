# Run this complete file once, while connected to the internet.
# R packages add tools to R. Both workshops use the same installed library.
packages <- c(
  jsonlite = "Reads the settings and result summaries saved as JSON.",
  terra = "Reads and calculates with maps made of grid cells.",
  sf = "Reads and works with mapped points, lines and areas.",
  lwgeom = "Provides extra tools for fixing and measuring map shapes.",
  ggplot2 = "Draws charts and maps.",
  patchwork = "Puts several charts on one page.",
  ggspatial = "Adds useful map items such as scale bars.",
  ggrepel = "Keeps text labels from covering each other.",
  ggnewscale = "Gives different map layers their own colours and legends.",
  scales = "Makes axis labels, percentages and colour scales readable.",
  ragg = "Saves sharp images of plots.",
  png = "Reads PNG images for reports.",
  systemfonts = "Finds fonts installed on your computer.",
  openxlsx = "Reads and writes Excel tables without opening Excel.",
  exactextractr = "Summarises grid-cell values inside mapped areas.",
  lme4 = "Fits models that account for repeated visits to the same fire.",
  emmeans = "Summarises and compares values estimated by a model.",
  spdep = "Checks whether nearby observations behave similarly.",
  lpSolve = "Finds a combination of candidates that meets the stated rules.",
  stringr = "Organises labels and other text.",
  maptiles = "Reads map backgrounds when a background tile source is used.",
  tidyterra = "Draws selected grid layers on a map.",
  zip = "Creates ZIP archives for optional field materials."
)

# Check which packages are already installed and add only the missing ones.
missing <- setdiff(names(packages), rownames(installed.packages()))
if (length(missing) > 0) {
  print(packages[missing])
  install.packages(missing, repos = "https://cloud.r-project.org")
}

# Check that R can open every package. This check also works offline.
failed <- names(packages)[!vapply(names(packages), requireNamespace, logical(1), quietly = TRUE)]
if (length(failed) > 0) {
  stop("R could not open these packages: ", paste(failed, collapse = ", "),
       ". Install or repair them before starting a lesson.", call. = FALSE)
}
message("Setup complete. All workshop packages are ready.")
