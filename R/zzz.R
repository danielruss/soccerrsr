.onLoad <- function(libname, pkgname) {
  if (.Platform$OS.type == "windows") {
    ort_dll <- system.file(
      "libs", .Platform$r_arch, "onnxruntime.dll",
      package = pkgname
    )
    if (nzchar(ort_dll) && file.exists(ort_dll)) {
      Sys.setenv(ORT_DYLIB_PATH = ort_dll)
    } else {
      warning(
        "onnxruntime.dll not found alongside the installed package. ",
        "The soccer-rs pipeline may fail to initialize on Windows."
      )
    }
  }
}