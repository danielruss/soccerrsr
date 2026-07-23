#' @useDynLib soccerrsr, .registration = TRUE
NULL

#' Occupation or Industry coding
#'
#' Classifies job descriptions or product/service descriptions into occupational
#' or industry codes. `run_soccernet()` codes jobs into US SOC 2010 codes.
#' `run_clips()` codes products and services into industry
#' classifications. SOCcerNET can use optional soc1980, noc2011, or isco1988
#' columns to assist in the soc2010 coding.  CLIPS can use a sic1987 columns.
#'
#' @param df A data frame containing the text to classify. See Details for
#'   required columns.
#' @param n Number of candidate codes to return per row (default: `10`)
#' @param block_size Number of rows to process per batch, tune for performance
#'   (default: `8` for SOCcerNET, `20` for CLIPS)
#'
#' @return The input data frame with additional columns containing the top `n`
#'   classification codes and their scores, joined by `Id`.
#'
#' @details
#' ## Required columns
#'
#' **`run_soccernet()`** requires:
#' - `JobTitle` — job title text *(required)*
#' - `JobTask` — job task description
#'  *(optional, created as empty string if missing)*
#' - `Id` — unique row identifier
#'  *(optional, auto-generated as `row-001`, `row-002`, etc. if missing)*
#'
#' Optionally, crosswalk columns `soc1980`, `noc2011`, and `isco1988` can be
#' provided as lists or character vectors.
#'
#' **`run_clips()`** requires:
#' - `products_services` — product or service description *(required)*
#' - `Id` — unique row identifier *(optional, auto-generated if missing)*
#'
#' ## Performance
#' `block_size` controls how many rows are processed at once. Larger values
#' may improve throughput but use more memory. Tune based on your hardware.
#'
#' @examples
#' \dontrun{
#' # SOCcerNET
#' df <- data.frame(
#'   JobTitle = c("Staff Scientist", "Data Engineer"),
#'   JobTask  = c("Develop chemical assays", "Build data pipelines")
#' )
#' run_soccernet(df)
#' run_soccernet(df, n = 5, block_size = 16)
#'
#' # CLIPS
#' df <- data.frame(products_services =
#'   c("Software development", "Cloud hosting"))
#' run_clips(df)
#' }
#'
#' @seealso [embed_jobs()]
#'
#' @aliases soccernet CLIPS clips run_soccernet run_clips
#' @name SOCcerNET
#' @export
run_soccernet <- function(df,n=10,block_size=8){
  if (!"JobTitle" %in% names(df)) {
    stop("data requires as a mininum a JobTitle column")
  }
  if (!"Id" %in% names(df)){
    cat("...SOCcerNET requires an Id column, since you did not provide one, I am creating one with the format row-xxx where xxx is the row number\n")
    num_chars=floor(log10(nrow(df)))+1
    df["Id"]=paste0("row-",stringr::str_pad(1:nrow(df),num_chars,"left","0") )
    df <- df |> dplyr::relocate("Id")
  }
  if (!"JobTask" %in% names(df)){
    cat("...You did not supply a JobTask column... filling with empty strings\n")
    df["JobTask"] = ""
  }
  xw_cols <- c("soc1980","noc2011","isco1988")
  df1 <- df |> dplyr::mutate(dplyr::across(dplyr::any_of(xw_cols),\(c){if (is.list(c)) {c} else {as.list(c)}}) )
  res <- soccer_net(df1,n,block_size)
  df |> dplyr::left_join(res,by="Id")
}


#' @export
#' @rdname SOCcerNET
run_clips <- function(df,n=10,block_size=20){
  if (!"products_services" %in% names(df)) {
    stop("data requires as a mininum a products_services column")
  }
  if (!"Id" %in% names(df)){
    cat("...Clips requires an Id column, since you did not provide one, I am creating one with the format row-xxx where xxx is the row number\n")
    num_chars=floor(log10(nrow(df)))+1
    df["Id"]=paste0("row-",stringr::str_pad(1:nrow(df),num_chars,"left","0") )
    df <- df |> dplyr::relocate("Id")
  }

  cat("Running CLIPS...")
  res <- clips(df,n,block_size)
  df |> dplyr::left_join(res,by="Id")
}

#' Embed job descriptions or product/service descriptions
#'
#' Generates dense vector embeddings using the GIST-small-Embedding model.
#' Automatically detects the type of input based on column names.
#'
#' @param df A data frame containing either:
#'   - `products_services` — for CLIPS data
#'   - `JobTitle` — for SOCcerNET data
#'   - `JobTask` **optional** - only if `JobTitle` is provided
#' @param text1 A single character string to embed
#' (job title or product/service)
#' @param text2 An optional single character string for additional context
#' (job task)
#'
#' @return A numeric vector of length 384 (`embed_job`) or a numeric matrix
#'   of shape `n x 384` (`embed_jobs`) where each row is an embedding.
#'
#' @details
#' NA values in `JobTitle`, `products_services`, or `JobTask`
#' will be replaced with a single space character and a warning will be issued
#' indicating which rows are affected.
#'
#' @examples
#' \dontrun{
#' # Single embedding
#' embed_job("Doctor", "Diagnose patients")
#' embed_job("Doctor")
#'
#' # Batch embedding - SOCcerNET
#' df <- data.frame(JobTitle = c("Doctor", "Lawyer"),
#' JobTask = c("Diagnose patients", "Draft contracts"))
#' embed_jobs(df)
#'
#' # Batch embedding - CLIPS
#' df <- data.frame(products_services =
#'   c("Software development", "Cloud hosting"))
#' embed_jobs(df)
#' }
#'
#' @seealso [SOCcerNET]
#' @name embed
#' @export
embed_job <- function(text1,text2=NULL){
  stopifnot(is.character(text1), length(text1) == 1, nchar(text1)>0)
  stopifnot(is.null(text2) || (is.character(text2) && length(text2) == 1 && nchar(text2)>0))
  .Call(wrap__embed_job, text1, text2)
}

#' @rdname embed
#' @export
embed_jobs <- function(df){
  t2 <- NULL
  t2_name <- NULL
  if ("products_services" %in% names(df)) {
    # CLIPS
    t1 <- df$products_services
    t1_name <- "products_services"
  } else if ("JobTitle" %in% names(df)){
    #SOCcerNET
    t1 <- df$JobTitle
    t1_name <- "JobTitle"
    if ("JobTask" %in% names(df)){
      t2 <- df$JobTask
      t2_name <- "JobTask"
    }
  } else {
    stop("the data frame has neither JobTitle or products_services")
  }

  if (any(is.na(t1))) {
    warning(paste(t1_name, "contains NA values, they will be embedded as a space character.  Rows:",paste(which(is.na(t1)),collapse=", ")))
    t1[is.na(t1)] = " "
  }

  if (is.null(t2)){
    .Call(wrap__embed_jobs,t1,NULL)
  }else{
    if (any(is.na(t2))) {
      warning(paste(t2_name, "contains NA values, they will be embedded as a space character.  Rows:",paste(which(is.na(t2)),collapse=", ") ))
      t2[is.na(t2)] = " "
    }
    .Call(wrap__embed_jobs,t1,t2)
  }  |> matrix(nrow=length(t1),byrow=TRUE)
}
