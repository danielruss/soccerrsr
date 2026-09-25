# soccerrsr

`soccerrsr` brings the SOCcerNET occupation classifier and the CLIPS
industry classifier to R. Classification and text embedding run locally using
Rust and ONNX Runtime.

## Installation

Install the released package from R-universe:

```r
install.packages(
  "soccerrsr",
  repos = c(
    "https://danielruss.r-universe.dev",
    "https://cloud.r-project.org"
  )
)
```

Building the package from source requires R 4.2 or later, Rust 1.85 or later,
Cargo, `xz`, and a working C/C++ toolchain.

## Classify occupations with SOCcerNET

`run_soccernet()` classifies job descriptions using US SOC 2010 codes:

```r
library(soccerrsr)

jobs <- data.frame(
  JobTitle = c("Staff Scientist", "Data Engineer"),
  JobTask = c("Develop chemical assays", "Build data pipelines")
)

result <- run_soccernet(jobs, n = 4)
result
```

The input must contain `JobTitle`. `JobTask` is optional and defaults to an
empty string. If `Id` is absent, the package creates identifiers such as
`row-1` and `row-2`. The returned data frame contains the original columns
plus the requested candidate codes and scores.

Optional `soc1980`, `noc2011`, and `isco1988` columns can provide crosswalk
information to assist classification.

## Classify Industry with CLIPS

`run_clips()` classifies product and service descriptions into NAICS 2022 5-digit 
industry codes:

```r
items <- data.frame(
  products_services = c("Software development", "Cloud hosting")
)

result <- run_clips(items, n = 5)
result
```

The input must contain `products_services`. An `Id` column is optional, and a
`sic1987` column can provide additional classification information.

## Create embeddings

The package can also generate 384-dimensional embeddings with the
GIST-small-Embedding model:

```r
# One job description
embedding <- embed_job("Doctor", "Diagnose patients")
length(embedding)

# A batch of job descriptions
job_embeddings <- embed_jobs(
  data.frame(
    JobTitle = c("Doctor", "Lawyer"),
    JobTask = c("Diagnose patients", "Draft contracts")
  )
)
dim(job_embeddings)
```

`embed_jobs()` also accepts a data frame containing a `products_services`
column.

## Performance

Classification is performed in batches. The `block_size` argument controls
the number of rows processed together:

```r
result <- run_soccernet(jobs, n = 5, block_size = 16)
```

Larger blocks may improve throughput but require more memory. The defaults
are 8 for SOCcerNET and 20 for CLIPS.

## Supported platforms

Source builds are tested on:

- macOS on Apple Silicon
- macOS on Intel x86_64
- Windows x86_64
- Linux x86_64

## License

MIT
