# Inputs must be comparable, masked, metadata-scaled surface reflectance.
nbr <- function(nir, swir2, epsilon = 1e-6) {
  denominator <- nir + swir2
  result <- (nir - swir2) / denominator
  result[abs(denominator) < epsilon] <- NA_real_
  result
}

# pre_nbr and post_nbr are unscaled NBR (-1 to 1).
# dnbr is unscaled; dnbr_x1000 and rdnbr follow the Miller & Thode (2007)
# convention (NBR x 1000), so published thresholds such as RdNBR 316/641 apply
# directly: RdNBR = dNBR_x1000 / sqrt(|preNBR_x1000 / 1000|) = 1000 * dnbr / sqrt(|pre_nbr|).
# Any thresholds used for Bhutan still require local field validation.
severity_indices <- function(pre_nbr, post_nbr, epsilon = 1e-6) {
  dnbr <- pre_nbr - post_nbr
  rdnbr <- 1000 * dnbr / sqrt(abs(pre_nbr))
  rdnbr[abs(pre_nbr) < epsilon] <- NA_real_
  list(dnbr = dnbr, dnbr_x1000 = 1000 * dnbr, rdnbr = rdnbr)
}
