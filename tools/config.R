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
is_linux <- identical(Sys.info()[["sysname"]], "Linux")
is_macos_x86_64 <- identical(Sys.info()[["sysname"]], "Darwin") &&
  identical(R.version$arch, "x86_64")

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

# --- ONNX Runtime shared libraries (Linux only) ---
# The static archive downloaded by ort-sys can require a newer glibc than the
# target system. Load Microsoft's shared runtime dynamically instead and bundle
# it beside the installed R package shared library.
ort_linux_sha256 <- "782564d3d68e87269ea1812cc94710ad06fe014faf093f01a6f89d0bd58719d3"
ort_linux_files <- c(
  "libonnxruntime.so",
  "libonnxruntime_providers_shared.so"
)
ort_linux_relpaths <- file.path("src", ort_linux_files)

if (is_linux) {
  ort_linux_runtime <- switch(
    R.version$arch,
    x86_64 = "linux-x64",
    aarch64 = "linux-arm64",
    stop("Unsupported Linux architecture for ONNX Runtime: ", R.version$arch)
  )

  if (!all(file.exists(ort_linux_relpaths))) {
    message("Fetching ONNX Runtime ", ort_version, " for Linux...")

    url <- sprintf(
      paste0(
        "https://api.nuget.org/v3-flatcontainer/microsoft.ml.onnxruntime/",
        "%s/microsoft.ml.onnxruntime.%s.nupkg"
      ),
      ort_version,
      ort_version
    )
    tmp_zip <- tempfile(fileext = ".nupkg")
    tmp_dir <- tempfile()
    archive_files <- file.path(
      "runtimes",
      ort_linux_runtime,
      "native",
      ort_linux_files
    )

    tryCatch(
      {
        download.file(url, tmp_zip, mode = "wb", quiet = FALSE)
        actual_sha256 <- unname(tools::sha256sum(tmp_zip))
        if (!identical(actual_sha256, ort_linux_sha256)) {
          stop("ONNX Runtime NuGet package checksum mismatch")
        }

        unzip(tmp_zip, files = archive_files, exdir = tmp_dir)
        extracted_files <- file.path(tmp_dir, archive_files)
        missing_files <- extracted_files[!file.exists(extracted_files)]
        if (length(missing_files) > 0L) {
          stop("Expected Linux runtime file not found: ", missing_files[[1L]])
        }

        copied <- file.copy(
          extracted_files,
          ort_linux_relpaths,
          overwrite = TRUE
        )
        if (!all(copied)) {
          stop("Failed to copy ONNX Runtime Linux shared libraries into src/")
        }
        message("ONNX Runtime Linux shared libraries placed in src/")
      },
      error = function(e) stop("Failed to fetch Linux ONNX Runtime: ", conditionMessage(e)),
      finally = {
        unlink(tmp_zip)
        unlink(tmp_dir, recursive = TRUE)
      }
    )
  } else {
    message("ONNX Runtime Linux shared libraries already present, skipping download.")
  }
}

# --- ONNX Runtime dylib fetch (Intel macOS only) ---
# ort no longer publishes an x86_64-apple-darwin binary. This custom build is
# loaded dynamically and bundled beside the installed R package shared library.
ort_macos_archive <- sprintf("onnxruntime-macos-x86_64-%s.tar.gz", ort_version)
ort_macos_dylib <- sprintf("libonnxruntime.%s.dylib", ort_version)
ort_macos_dylib_relpath <- file.path("src", ort_macos_dylib)
ort_macos_sha256 <- "57853607712285595b6a60598020ce8d0c2558a4028a24769bd0cb422d007759"

if (is_macos_x86_64) {
  if (!file.exists(ort_macos_dylib_relpath)) {
    message("Fetching ONNX Runtime ", ort_version, " for Intel macOS...")

    url <- sprintf(
      paste0(
        "https://github.com/danielruss/custom-ort-macos-x86-64/",
        "releases/download/v%s/%s"
      ),
      ort_version,
      ort_macos_archive
    )
    tmp_tar <- tempfile(fileext = ".tar.gz")

    tryCatch(
      {
        download.file(url, tmp_tar, mode = "wb", quiet = FALSE)
        actual_sha256 <- unname(tools::sha256sum(tmp_tar))
        if (!identical(actual_sha256, ort_macos_sha256)) {
          stop("ONNX Runtime archive checksum mismatch")
        }
        utils::untar(tmp_tar, files = ort_macos_dylib, exdir = "src")
        if (!file.exists(ort_macos_dylib_relpath)) {
          stop("Expected dylib not found after extraction: ", ort_macos_dylib)
        }
        message(ort_macos_dylib, " placed in src/")
      },
      error = function(e) stop("Failed to fetch Intel macOS ONNX Runtime: ", conditionMessage(e)),
      finally = unlink(tmp_tar)
    )
  } else {
    message(ort_macos_dylib, " already present, skipping download.")
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
