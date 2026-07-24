library(soccerrsr)
library(assertthat)

df <- data.frame(
  JobTitle = c("Staff Scientist", "Data Engineer"),
  JobTask  = c("Develop chemical assays", "Build data pipelines")
)
expected <- data.frame(
  soc2010_1 = c("19-4031","15-1199"),
  score_1 = c(0.9588,0.2335),
  soc2010_2 = c("19-2031","15-1141"),
  score_2 = c(0.5039,0.1019),
  soc2010_3 = c("19-4021","15-1132"),
  score_3 = c(0.0795,0.0177),
  soc2010_4 = c("19-1021","15-1143"),
  score_4 = c(0.0619,0.0143)
)
res <- run_soccernet(df,n=4)
check_codes <- paste0("soc2010_",1:4) |>
  purrr::set_names() |>
  purrr::map_lgl(\(x) assertthat::are_equal(res[[x]], expected[[x]]))
check_score <- paste0("score_",1:4) |>
  purrr::set_names() |>
  purrr::map_lgl(\(x) assertthat::are_equal(res[[x]], expected[[x]],tol=0.0001,
                                            scale=1))

if (!all(check_codes) || !all(check_score)) {
  stop("soccernet test failed: output does not match expected values.")
}

cat("All checks passed.\n")
