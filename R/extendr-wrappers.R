#' This is my function documentation

# nolint start

#' @export
soccer_net <- function(df, n, block_size) .Call(wrap__soccer_net, df, n, block_size)

#' This is my function documentation
#' @export
clips <- function(df, n, block_size) .Call(wrap__clips, df, n, block_size)


# nolint end
