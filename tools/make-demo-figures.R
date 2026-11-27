# Run from the training-site directory to rebuild the public synthetic figures.
render_demo <- function(workshop, draw) {
  values <- new.env()
  invisible(capture.output(sys.source(file.path("src", "examples",
    paste0(workshop, "-demo.R")), envir = values)))
  png(file.path("src", "assets", paste0(workshop, "-demo.png")),
    width = 1040, height = 470, res = 130, bg = "#f7f6ef")
  on.exit(dev.off())
  par(mar = c(4.1, 5.0, 1.8, 1), fg = "#172d27", col.axis = "#172d27",
    col.lab = "#172d27", las = 1, bty = "n")
  draw(values)
}

render_demo("wui", function(values) {
  area <- values$area
  palette <- c(intermix = "#176451", interface = "#a14b27", other = "#83968a")
  at <- barplot(area$buildings, names.arg = area$place, col = palette[area$class],
    border = NA, ylim = c(0, 44), xlab = "Synthetic neighbourhood",
    ylab = "Buildings per square kilometre")
  abline(h = 20, lty = "dashed", col = "#4f645c")
  text(at, area$buildings + 2, labels = area$class, cex = .84)
})

render_demo("burn", function(values) {
  barplot(values$corrected, names.arg = c("Target", "Reference 1", "Reference 2", "Reference 3"),
    col = c("#a14b27", rep("#83968a", 3)), border = NA, ylim = c(-.02, .55),
    xlab = "Synthetic pixels", ylab = "Corrected dNBR")
  abline(h = 0, col = "#4f645c")
})
