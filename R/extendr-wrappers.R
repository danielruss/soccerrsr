#' Run SOCcerNET from R

soccer_net <- function(df, n, block_size) .Call(wrap__soccer_net, df, n, block_size)

#' Run clips
clips <- function(df, n, block_size) .Call(wrap__clips, df, n, block_size)

#' Embed a job
embed_job <- function(text1, text2) .Call(wrap__embed_job, text1, text2)
embed_jobs <- function(text1, text2) .Call(wrap__embed_jobs, text1, text2)


# nolint end
