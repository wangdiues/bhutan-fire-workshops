# Publication-figure workflow following renv/scientific-figure-skill (sci-figure), in R/ggplot2.
# The skill is written for matplotlib; the project environment is R, so the same rules apply here:
# configuration block, separate output folder, data-health report before plotting, process data
# as numbered .xlsx, serif type, grayscale first (Okabe-Ito only when needed, viridis/cividis for
# sequential maps), full four-sided frame, units in parentheses, no in-chart titles, three-part
# captions, pdf+png+jpg for every figure, and a bundled report.pdf.
suppressPackageStartupMessages({ library(ggplot2); library(openxlsx) })

# ============================================================
# CONFIGURATION (shared defaults; scripts may override fields)
# ============================================================
SCI <- list(
  formats = c("pdf", "png", "jpg"), dpi = 300,
  en_serif = c("Times New Roman", "Liberation Serif", "DejaVu Serif", "serif"),
  alpha = 0.05, sig_marks = c(`0.001` = "***", `0.01` = "**", `0.05` = "*"), ns_label = "ns",
  error_bar = "CI95", decimals = 3, sci_low = 1e-3, sci_high = 1e5,
  fig_single = c(3.5, 2.6), fig_double = c(7.2, 4.0),
  grey = c("#000000", "#555555", "#888888", "#bbbbbb"),
  okabe_ito = c("#000000", "#E69F00", "#56B4E9", "#009E73", "#F0E442", "#0072B2", "#D55E00", "#CC79A7"),
  class5 = c("#1a9850", "#a6d96a", "#fee08b", "#f46d43", "#a50026")  # diverging, ordered classes only
)
# ============================================================

sci_font <- function() {
  have <- unique(systemfonts::system_fonts()$family)
  for (f in SCI$en_serif) if (f %in% have || f == "serif") return(f)
  "serif"
}
SCI$font <- sci_font()

theme_sci <- function(base_size = 10) {
  theme_bw(base_size = base_size, base_family = SCI$font) +
    theme(panel.border = element_rect(colour = "black", fill = NA, linewidth = 0.8),
          panel.grid.major = element_line(colour = "#e5e5e5", linewidth = 0.5),
          panel.grid.minor = element_blank(),
          axis.text = element_text(colour = "black", size = base_size - 1),
          axis.title = element_text(colour = "black", size = base_size),
          axis.ticks = element_line(colour = "black", linewidth = 0.4),
          legend.key = element_blank(), legend.background = element_blank(),
          legend.text = element_text(size = base_size - 1), legend.title = element_text(size = base_size - 1),
          strip.background = element_rect(fill = "white", colour = "black", linewidth = 0.8),
          strip.text = element_text(colour = "black", size = base_size - 1),
          plot.title = element_blank(), plot.subtitle = element_blank(), plot.caption = element_blank(),
          plot.background = element_rect(fill = "white", colour = NA))
}

# Map variant: keeps the frame, drops the grid and coordinate ticks.
theme_sci_map <- function(base_size = 10) {
  theme_sci(base_size) + theme(panel.grid.major = element_blank(), axis.text = element_blank(),
                               axis.ticks = element_blank(), axis.title = element_blank())
}

smart_format <- function(x) {
  vapply(x, function(v) {
    if (is.na(v)) return(NA_character_)
    if (v == 0) return("0")
    a <- abs(v)
    if (a < SCI$sci_low || a >= SCI$sci_high) return(formatC(v, format = "e", digits = 1))
    if (a >= 1000) return(formatC(v, format = "f", digits = ifelse(v == round(v), 0, 1), big.mark = ","))
    format(signif(v, SCI$decimals), trim = TRUE, scientific = FALSE)
  }, character(1))
}
format_p <- function(p) ifelse(p < 0.001, "p < 0.001", ifelse(p < 0.01, sprintf("p = %.3f", p), sprintf("p = %.2f", p)))
sig_mark <- function(p) {
  if (is.na(p) || p >= SCI$alpha) return(SCI$ns_label)
  for (t in sort(as.numeric(names(SCI$sig_marks)))) if (p < t) return(SCI$sig_marks[[as.character(t)]])
  SCI$ns_label
}

# ---- run folder -----------------------------------------------------------------------------
sci_run <- function(slug, title, inputs = character()) {
  dir <- file.path(if (exists("SCI_OUT_ROOT")) SCI_OUT_ROOT else "outputs/analysis", slug)
  for (s in c("figures/pdf", "figures/png", "figures/jpg", "process_data")) dir.create(file.path(dir, s), recursive = TRUE, showWarnings = FALSE)
  in_dirs <- unique(normalizePath(dirname(inputs), mustWork = FALSE))
  if (normalizePath(dir, mustWork = FALSE) %in% in_dirs) stop("Output folder equals an input folder.")
  run <- new.env()
  run$dir <- dir; run$title <- title; run$captions <- list(); run$health <- character(); run$process_n <- 0
  message("Outputs: ", dir)
  run
}

# ---- process data (.xlsx) ------------------------------------------------------------------------
write_process <- function(run, df, name) {
  run$process_n <- run$process_n + 1
  file <- file.path(run$dir, "process_data", sprintf("%02d_%s.xlsx", run$process_n, name))
  wb <- createWorkbook(); addWorksheet(wb, "data")
  writeData(wb, "data", df, headerStyle = createStyle(textDecoration = "bold", border = "bottom"))
  freezePane(wb, "data", firstRow = TRUE); setColWidths(wb, "data", seq_along(df), "auto")
  saveWorkbook(wb, file, overwrite = TRUE)
  invisible(file)
}

# ---- figures ------------------------------------------------------------------------------------
save_fig <- function(run, plot, n, slug, data, caption, size = SCI$fig_double) {
  stopifnot(length(caption) == 3)  # what, how, so what
  base <- sprintf("fig_%02d_%s", n, slug)
  for (fmt in SCI$formats) {
    path <- file.path(run$dir, "figures", fmt, paste0(base, ".", fmt))
    if (fmt == "pdf") ggsave(path, plot, width = size[1], height = size[2], device = cairo_pdf)
    else ggsave(path, plot, width = size[1], height = size[2], dpi = SCI$dpi, device = if (fmt == "png") ragg::agg_png else ragg::agg_jpeg)
  }
  write_process_fig(run, data, n)
  run$captions[[base]] <- list(n = n, text = sprintf("Figure %d. %s %s %s", n, caption[1], caption[2], caption[3]),
                               png = file.path(run$dir, "figures", "png", paste0(base, ".png")), size = size)
  invisible(base)
}
write_process_fig <- function(run, data, n) {
  file <- file.path(run$dir, "process_data", sprintf("fig_%02d_data.xlsx", n))
  wb <- createWorkbook(); addWorksheet(wb, "data")
  writeData(wb, "data", as.data.frame(data), headerStyle = createStyle(textDecoration = "bold", border = "bottom"))
  freezePane(wb, "data", firstRow = TRUE); saveWorkbook(wb, file, overwrite = TRUE)
}

# ---- data health (00_data_health.md) ---------------------------------------------------------------
md_table <- function(df, digits = 3) {
  if (!nrow(df)) return("(none)")
  df[] <- lapply(df, function(x) if (is.numeric(x)) format(round(x, digits), trim = TRUE, big.mark = ",") else as.character(x))
  c(paste("|", paste(names(df), collapse = " | "), "|"), paste("|", paste(rep("---", ncol(df)), collapse = " | "), "|"),
    apply(df, 1, function(r) paste("|", paste(r, collapse = " | "), "|")))
}
data_health <- function(run, df, name, max_vif_cols = 15) {
  df <- as.data.frame(df)
  findings <- list(warnings = character(), normality = list(), vif_flags = character())
  L <- c(sprintf("## Dataset: %s", name), "",
         sprintf("- Rows: %s", format(nrow(df), big.mark = ",")), sprintf("- Columns: %d", ncol(df)),
         sprintf("- Memory: %.2f MB", as.numeric(object.size(df)) / 1024^2), "")
  inv <- data.frame(column = names(df), type = vapply(df, function(x) class(x)[1], ""),
                    missing = vapply(df, function(x) sum(is.na(x)), 0),
                    missing_pct = vapply(df, function(x) 100 * mean(is.na(x)), 0),
                    n_unique = vapply(df, function(x) length(unique(x)), 0))
  L <- c(L, "### Per-column inventory", "", md_table(inv, 2), "")
  hi <- inv$column[inv$missing_pct > 30]
  if (length(hi)) findings$warnings <- c(findings$warnings, sprintf("%s: columns with >30%% missing: %s", name, paste(hi, collapse = ", ")))
  L <- c(L, "### Duplicate rows", "", sprintf("- Fully duplicated rows: %d", sum(duplicated(df))), "")
  num <- names(df)[vapply(df, is.numeric, TRUE)]
  if (length(num)) {
    desc <- do.call(rbind, lapply(num, function(c) { s <- df[[c]][is.finite(df[[c]])]
      q <- if (length(s)) quantile(s, c(0, .25, .5, .75, 1)) else rep(NA, 5)
      sk <- if (length(s) > 2 && sd(s) > 0) mean((s - mean(s))^3) / sd(s)^3 else NA
      data.frame(column = c, n = length(s), mean = mean(s), sd = sd(s), min = q[1], q25 = q[2], median = q[3], q75 = q[4], max = q[5], skew = sk) }))
    rownames(desc) <- NULL
    L <- c(L, "### Numeric columns", "", md_table(desc), "")
    norm <- do.call(rbind, lapply(num, function(c) { s <- df[[c]][is.finite(df[[c]])]
      if (length(s) < 3 || length(unique(s)) < 3) return(data.frame(column = c, test = "n/a", p_value = NA, verdict = "insufficient"))
      if (length(s) < 5000) { p <- shapiro.test(s)$p.value; t <- "Shapiro-Wilk" }
      else { p <- suppressWarnings(ks.test(s, "pnorm", mean(s), sd(s))$p.value); t <- "Kolmogorov-Smirnov" }
      data.frame(column = c, test = t, p_value = p, verdict = ifelse(p >= SCI$alpha, "normal", "not normal")) }))
    for (i in seq_len(nrow(norm))) findings$normality[[norm$column[i]]] <- norm$verdict[i] == "normal"
    L <- c(L, "#### Normality", "", md_table(norm, 4), "")
    out <- do.call(rbind, lapply(num, function(c) { s <- df[[c]][is.finite(df[[c]])]
      q <- quantile(s, c(.25, .75), na.rm = TRUE); iqr <- diff(q)
      n <- sum(s < q[1] - 1.5 * iqr | s > q[2] + 1.5 * iqr)
      data.frame(column = c, n_outliers = n, pct = 100 * n / max(1, length(s))) }))
    L <- c(L, "#### Outliers (IQR rule)", "", md_table(out, 2), "")
  }
  cat_cols <- names(df)[vapply(df, function(x) is.character(x) || is.factor(x) || is.logical(x), TRUE)]
  if (length(cat_cols)) {
    L <- c(L, "### Categorical columns", "")
    for (c in cat_cols) {
      x <- as.character(df[[c]]); top <- sort(table(x, useNA = "ifany"), decreasing = TRUE)[1:min(5, length(unique(x)))]
      ws <- any(!is.na(x) & trimws(x) != x)
      if (ws) findings$warnings <- c(findings$warnings, sprintf("%s: `%s` has leading/trailing whitespace", name, c))
      L <- c(L, sprintf("#### `%s`", c), sprintf("- Unique categories: %d", length(unique(x))),
             sprintf("- Whitespace issues: %s", ifelse(ws, "yes", "no")), "",
             md_table(data.frame(value = names(top), count = as.integer(top))), "")
    }
  }
  vnum <- num[vapply(num, function(c) isTRUE(sd(df[[c]], na.rm = TRUE) > 0), TRUE)]   # isTRUE: sd is NA with < 2 values
  vnum <- head(vnum, max_vif_cols)
  if (length(vnum) >= 3) {
    X <- df[complete.cases(df[vnum]), vnum, drop = FALSE]
    if (nrow(X) > 5000) X <- X[sample(nrow(X), 5000), , drop = FALSE]
    cm <- round(cor(X, method = "spearman"), 2)
    L <- c(L, "### Multicollinearity", "", "Spearman correlation matrix:", "", md_table(cbind(column = rownames(cm), as.data.frame(cm)), 2), "")
    if (nrow(X) > length(vnum) + 1) {
      vif <- vapply(vnum, function(c) { r2 <- summary(lm(X[[c]] ~ ., data = X[setdiff(vnum, c)]))$r.squared; 1 / (1 - r2) }, 0)
      flag <- ifelse(vif > 10, "severe", ifelse(vif > 5, "moderate", ""))
      findings$vif_flags <- c(findings$vif_flags, sprintf("%s:%s(%.1f)", name, vnum[flag != ""], vif[flag != ""]))
      L <- c(L, "Variance inflation factor (VIF > 5 moderate, > 10 severe):", "", md_table(data.frame(column = vnum, VIF = vif, flag = flag), 2), "")
    }
  }
  if (length(findings$warnings)) L <- c(L, "### Warnings", "", paste("-", findings$warnings), "")
  run$health <- c(run$health, L)
  run$findings <- c(run$findings, list(findings))
  invisible(findings)
}
write_health <- function(run, notes = character()) {
  writeLines(c(sprintf("# Data health report: %s", run$title), "",
               sprintf("Generated %s. Produced before any figure was drawn.", format(Sys.time(), "%Y-%m-%d %H:%M")), "",
               if (length(notes)) c("## Analyst notes", "", paste("-", notes), "") else NULL, run$health),
             file.path(run$dir, "00_data_health.md"))
}

# ---- report.pdf --------------------------------------------------------------------------------------
build_report <- function(run, intro = character()) {
  caps <- run$captions[order(vapply(run$captions, `[[`, 0, "n"))]
  writeLines(c(sprintf("# Figure captions: %s", run$title), "", unlist(lapply(caps, function(x) c(x$text, "")))),
             file.path(run$dir, "captions.md"))
  pdf_file <- file.path(run$dir, "report.pdf")
  cairo_pdf(pdf_file, width = 8.27, height = 11.69, family = SCI$font, onefile = TRUE)
  on.exit(dev.off())
  wrap <- function(x, w) paste(strwrap(x, w), collapse = "\n")
  grid::grid.newpage()
  grid::grid.text(run$title, y = 0.82, gp = grid::gpar(fontsize = 18, fontface = "bold"))
  grid::grid.text(sprintf("FIRE-BHUTAN | thimphu_paro_burn_severity package | %s", format(Sys.Date(), "%d %B %Y")), y = 0.77, gp = grid::gpar(fontsize = 11))
  if (length(intro)) grid::grid.text(wrap(paste(intro, collapse = " "), 95), y = 0.55, gp = grid::gpar(fontsize = 10))
  for (x in caps) {
    grid::grid.newpage()
    img <- png::readPNG(x$png)
    asp <- dim(img)[1] / dim(img)[2]
    w <- 0.86; h <- min(0.62, w * asp * 8.27 / 11.69)
    grid::grid.raster(img, x = 0.5, y = 0.93 - h / 2, width = grid::unit(h / asp * 11.69 / 8.27, "npc"), height = grid::unit(h, "npc"))
    grid::grid.text(wrap(x$text, 105), x = 0.07, y = 0.90 - h - 0.02, just = c("left", "top"),
                    gp = grid::gpar(fontsize = 9, fontface = "italic"))
  }
  invisible(pdf_file)
}

# Raster to data frame for ggplot maps (aggregated to keep files light).
raster_df <- function(r, fact = 1, fun = "modal") {
  if (fact > 1) r <- terra::aggregate(r, fact, fun = fun, na.rm = TRUE)
  d <- as.data.frame(r, xy = TRUE, na.rm = TRUE); names(d)[3] <- "value"; d
}
