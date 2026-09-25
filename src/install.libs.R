# src/install.libs.R
# Overrides R's default install step so we control exactly what lands in
# <pkg>/libs/<arch>/ — needed because we also ship ONNX Runtime, not just
# the compiled package shared library.

dest <- file.path(R_PACKAGE_DIR, paste0("libs", R_ARCH))
dir.create(dest, recursive = TRUE, showWarnings = FALSE)

# 1. The package's own compiled shared library (what R would have copied by default)
shlib_name <- paste0(R_PACKAGE_NAME, SHLIB_EXT)
if (file.exists(shlib_name)) {
  file.copy(shlib_name, file.path(dest, shlib_name), overwrite = TRUE)
} else {
  stop("Expected shared library not found: ", shlib_name,
       "\nThe Rust build (cargo build via Makevars", if (WINDOWS) ".win" else "", ") likely failed.")
}

# 2. The bundled ONNX Runtime DLL (Windows only — fetched earlier by tools/config.R)
if (WINDOWS) {
  ort_dll <- "onnxruntime.dll"
  if (file.exists(ort_dll)) {
    file.copy(ort_dll, file.path(dest, ort_dll), overwrite = TRUE)
    message("Copied onnxruntime.dll to ", dest)
  } else {
    warning("onnxruntime.dll not found in src/ at install time — did tools/config.R run?")
  }
}

# 3. The bundled ONNX Runtime shared libraries (Linux only)
if (identical(Sys.info()[["sysname"]], "Linux")) {
  ort_linux_files <- c(
    "libonnxruntime.so",
    "libonnxruntime_providers_shared.so"
  )
  for (ort_so in ort_linux_files) {
    if (file.exists(ort_so)) {
      file.copy(ort_so, file.path(dest, ort_so), overwrite = TRUE)
      message("Copied ", ort_so, " to ", dest)
    } else {
      warning(ort_so, " not found in src/ at install time — did tools/config.R run?")
    }
  }
}

# 4. The custom ONNX Runtime dylib (Intel macOS only)
if (identical(Sys.info()[["sysname"]], "Darwin") &&
    identical(R.version$arch, "x86_64")) {
  ort_dylib <- "libonnxruntime.1.24.2.dylib"
  if (file.exists(ort_dylib)) {
    file.copy(ort_dylib, file.path(dest, ort_dylib), overwrite = TRUE)
    message("Copied ", ort_dylib, " to ", dest)
  } else {
    warning(ort_dylib, " not found in src/ at install time — did tools/config.R run?")
  }
}
