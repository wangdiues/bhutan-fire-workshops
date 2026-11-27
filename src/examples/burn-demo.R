# Synthetic exercise. Reflectance values represent four example pixels.
pixels <- data.frame(pre_nir = c(.55, .58, .51, .49), pre_swir = c(.17, .19, .19, .22),
                     post_nir = c(.31, .56, .50, .48), post_swir = c(.32, .20, .20, .23))

# Compute normalized burn ratio for each date and subtract post-fire NBR.
nbr <- function(nir, swir) (nir - swir) / (nir + swir)
pre <- with(pixels, nbr(pre_nir, pre_swir))
post <- with(pixels, nbr(post_nir, post_swir))
dnbr <- pre - post

# Use the three reference pixels to estimate background change.
corrected <- dnbr - median(dnbr[2:4])
print(round(data.frame(pre, post, dnbr, corrected), 3))
stopifnot(which.max(corrected) == 1, abs(median(corrected[2:4])) < 1e-10)
