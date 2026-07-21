#' Run SOCcerNET from R

# nolint start

initialize_onnx_runtime <- function(path) .Call(wrap__initialize_onnx_runtime, path)

soccer_net <- function(df, n, block_size) .Call(wrap__soccer_net, df, n, block_size)

#' Run clips
clips <- function(df, n, block_size) .Call(wrap__clips, df, n, block_size)

#' Embed a job
embed_job <- function(text1, text2) .Call(wrap__embed_job, text1, text2)

embed_jobs <- function(text1, text2) .Call(wrap__embed_jobs, text1, text2)


# nolint end
