is_intel_macos <- identical(Sys.info()[["sysname"]], "Darwin") &&
  identical(R.version$arch, "x86_64")
is_windows_gnu <- identical(.Platform$OS.type, "windows") &&
  grepl("mingw", R.version$platform, fixed = TRUE)
runtime_path <- Sys.getenv("ORT_DYLIB_PATH", unset = "")

if ((is_intel_macos || is_windows_gnu) && nzchar(runtime_path)) {
  library(soccerrsr)

  embedding <- embed_job("plumber")

  stopifnot(length(embedding) == 384L)
  stopifnot(all(is.finite(embedding)))
}
