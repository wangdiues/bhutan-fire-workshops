# Lesson 5.3 | Field kit: how the blind sample was drawn
# Run the setup first, then select the calculation or click Source for the whole file.
# Numerical examples describe the workshop dataset and settings.

# Create the analyst's example map labels, then draw two points per class.
set.seed(17)
pool <- data.frame(point = seq_len(12), mapped = rep(c("interface", "intermix", "other"), each = 4))
sampled <- do.call(rbind, lapply(split(pool, pool$mapped), function(rows) {
  rows[sample.int(nrow(rows), 2), ]
}))
print(table(sampled$mapped))

# Observers record their own class. The analyst joins labels by point after fieldwork.
observer_form <- data.frame(point = sort(sampled$point), observed = NA_character_)
print(observer_form, row.names = FALSE)
stopifnot(!"mapped" %in% names(observer_form))
