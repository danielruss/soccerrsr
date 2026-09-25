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

  if (identical(Sys.info()[["sysname"]], "Darwin") &&
      identical(R.version$arch, "x86_64")) {
    ort_dylib <- system.file(
      "libs", .Platform$r_arch, "libonnxruntime.1.24.2.dylib",
      package = pkgname
    )
    if (nzchar(ort_dylib) && file.exists(ort_dylib)) {
      Sys.setenv(ORT_DYLIB_PATH = ort_dylib)
    } else {
      warning(
        "Intel macOS ONNX Runtime dylib not found alongside the installed package. ",
        "The soccer-rs pipeline may fail to initialize."
      )
    }
  }
}
