#' @useDynLib soccerrsr, .registration = TRUE
NULL

#' Run SOCcerNET/CLIPS
#'
#' @param df data frame of data
#' @param n  the number of codes return (default=10)
#' @param block_size run the job in blocks to optimizer performance (default=8)
#'
#'
#' @export
run_soccernet <- function(df,n=10,block_size=8){
  if (!"JobTitle" %in% names(df)) {
    stop("data requires as a mininum a JobTitle column")
  }
  if (!"Id" %in% names(df)){
    cat("...SOCcerNET requires an Id column, since you did not provide one, I am creating one with the format row-xxx where xxx is the row number\n")
    num_chars=floor(log10(nrow(df)))+1
    df["Id"]=paste0("row-",stringr::str_pad(1:nrow(df),num_chars,"left","0") )
    df <- df |> dplyr::relocate(Id)
  }
  if (!"JobTasks" %in% names(df)){
    cat("...You did not supply a JobTask column... filling with empty strings\n")
    df["JobTask"] = ""
  }
  xw_cols <- c("soc1980","noc2011","isco1988")
  df1 <- df |> dplyr::mutate(dplyr::across(any_of(xw_cols),\(c){if (is.list(c)) {c} else {as.list(c)}}) )
  res <- soccer_net(df1,n,block_size)
  df |> dplyr::left_join(res,by="Id")
}


#' @rdname run_soccernet
#' @export
run_clips <- function(df,n=10,block_size=20){
  if (!"products_services" %in% names(df)) {
    stop("data requires as a mininum a products_services column")
  }
  if (!"Id" %in% names(df)){
    cat("...Clips requires an Id column, since you did not provide one, I am creating one with the format row-xxx where xxx is the row number\n")
    num_chars=floor(log10(nrow(df)))+1
    df["Id"]=paste0("row-",stringr::str_pad(1:nrow(df),num_chars,"left","0") )
    df <- df |> dplyr::relocate(Id)
  }

  cat("Running soccerNET...")
  res <- clips(df,n,block_size)
  df |> dplyr::left_join(res,by="Id")
}
