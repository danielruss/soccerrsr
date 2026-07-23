# Note: Any variables prefixed with `.` are used for text
# replacement in the Makevars.in and Makevars.win.in

# check the packages MSRV first
source("tools/msrv.R")

# check DEBUG and NOT_CRAN environment variables
env_debug <- Sys.getenv("DEBUG")
env_not_cran <- Sys.getenv("NOT_CRAN")

# check if the vendored zip file exists
vendor_exists <- file.exists("src/rust/vendor.tar.xz")

is_not_cran <- env_not_cran != ""
is_debug <- env_debug != ""

if (is_debug) {
  # if we have DEBUG then we set not cran to true
  # CRAN is always release build
  is_not_cran <- TRUE
  message("Creating DEBUG build.")
}

if (!is_not_cran) {
  message("Building for CRAN.")
}

# we set cran flags only if NOT_CRAN is empty and if
# the vendored crates are present.
.cran_flags <- ifelse(
  !is_not_cran && vendor_exists,
  "-j 2 --offline",
  ""
)

# when DEBUG env var is present we use `--debug` build
.profile <- ifelse(is_debug, "", "--release")
.clean_targets <- ifelse(is_debug, "", "$(TARGET_DIR)")

# We specify this target when building for webR
webr_target <- "wasm32-unknown-emscripten"

# here we check if the platform we are building for is webr
is_wasm <- identical(R.version$platform, webr_target)

# print to terminal to inform we are building for webr
if (is_wasm) {
  message("Building for WebR")
}

# we check if we are making a debug build or not
# if so, the LIBDIR environment variable becomes:
# LIBDIR = $(TARGET_DIR)/{wasm32-unknown-emscripten}/debug
# this will be used to fill out the LIBDIR env var for Makevars.in
target_libpath <- if (is_wasm) "wasm32-unknown-emscripten" else NULL
cfg <- if (is_debug) "debug" else "release"

# used to replace @LIBDIR@
.libdir <- paste(c(target_libpath, cfg), collapse = "/")

# use this to replace @TARGET@
# we specify the target _only_ on webR
# there may be use cases later where this can be adapted or expanded
.target <- ifelse(is_wasm, paste0("--target=", webr_target), "")

# add panic exports only for WASM builds
.panic_exports <- ifelse(
  is_wasm,
  "CARGO_PROFILE_DEV_PANIC=\"abort\" CARGO_PROFILE_RELEASE_PANIC=\"abort\" ",
  ""
)

# read in the Makevars.in file checking
is_windows <- .Platform[["OS.type"]] == "windows"

# if windows we replace in the Makevars.win.in
mv_fp <- ifelse(
  is_windows,
  "src/Makevars.win.in",
  "src/Makevars.in"
)

# set the output file
mv_ofp <- ifelse(
  is_windows,
  "src/Makevars.win",
  "src/Makevars"
)

# --- ONNX Runtime DLL fetch (Windows only) ---
# Needed because Rtools uses the GNU toolchain, but Microsoft only ships
# MSVC-format import libraries for onnxruntime.dll. soccer-rs's Cargo.toml
# uses `ort`'s `load-dynamic` feature on windows-gnu, which loads this DLL
# at runtime instead of linking it at compile time. install.libs.R bundles
# the DLL into the installed package; .onLoad() points ORT_DYLIB_PATH at it.

ort_version <- "1.24.2"  # keep in sync with the `ort` crate version pinned in soccer-rs/Cargo.toml
ort_dll_relpath <- "src/onnxruntime.dll"

if (is_windows) {
  if (!file.exists(ort_dll_relpath)) {
    message("Fetching ONNX Runtime ", ort_version, " for Windows...")

    url <- sprintf(
      "https://github.com/microsoft/onnxruntime/releases/download/v%s/onnxruntime-win-x64-%s.zip",
      ort_version, ort_version
    )

    tmp_zip <- tempfile(fileext = ".zip")
    tmp_dir <- tempfile()

    tryCatch(
      {
        download.file(url, tmp_zip, mode = "wb", quiet = FALSE)
        unzip(tmp_zip, exdir = tmp_dir)

        dll_src <- file.path(
          tmp_dir,
          sprintf("onnxruntime-win-x64-%s", ort_version),
          "lib", "onnxruntime.dll"
        )

        if (!file.exists(dll_src)) {
          stop("Expected DLL not found at: ", dll_src)
        }

        file.copy(dll_src, ort_dll_relpath, overwrite = TRUE)
        message("onnxruntime.dll placed at ", ort_dll_relpath)
      },
      error = function(e) stop("Failed to fetch ONNX Runtime DLL: ", conditionMessage(e)),
      finally = {
        unlink(tmp_zip)
        unlink(tmp_dir, recursive = TRUE)
      }
    )
  } else {
    message("onnxruntime.dll already present, skipping download.")
  }
}


# delete the existing Makevars{.win/.wasm}
if (file.exists(mv_ofp)) {
  message("Cleaning previous `", mv_ofp, "`.")
  invisible(file.remove(mv_ofp))
}

# read as a single string
mv_txt <- readLines(mv_fp)

# replace placeholder values
new_txt <- gsub("@CRAN_FLAGS@", .cran_flags, mv_txt) |>
  gsub("@PROFILE@", .profile, x = _) |>
  gsub("@CLEAN_TARGET@", .clean_targets, x = _) |>
  gsub("@LIBDIR@", .libdir, x = _) |>
  gsub("@TARGET@", .target, x = _) |>
  gsub("@PANIC_EXPORTS@", .panic_exports, x = _)

message("Writing `", mv_ofp, "`.")
con <- file(mv_ofp, open = "wb")
writeLines(new_txt, con, sep = "\n")
close(con)

message("`tools/config.R` has finished.")
