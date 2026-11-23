# Installs R packages from source with the R that runs it (the r-consumer
# CI job, slice2 PLAN.md D102/D113: r-zig-slim from universe and this run's
# zig-* packages), then fails unless every one of them loads:
#   Rscript tests/r/install.R <package> ...
# Their dependencies come from source too (CRAN, cloud mirror). Each
# package's install output stays in R_INSTALL_LOGS (default: a temporary
# directory) as <package>.out; the ones that did not install are printed.
args <- commandArgs(trailingOnly = TRUE)
if (!length(args)) stop("usage: Rscript tests/r/install.R <package> ...", call. = FALSE)
logs <- Sys.getenv("R_INSTALL_LOGS", file.path(tempdir(), "install-logs"))
dir.create(logs, recursive = TRUE, showWarnings = FALSE)
options(repos = c(CRAN = "https://cloud.r-project.org"), Ncpus = max(1L, parallel::detectCores() - 1L))
cat(R.version.string, "\n")
cat("libraries:", paste(.libPaths(), collapse = " "), "\n")
t0 <- Sys.time()
install.packages(args, type = "source", dependencies = c("Depends", "Imports", "LinkingTo"),
                 keep_outputs = logs, quiet = TRUE)
cat(sprintf("install.packages: %.1f min\n", as.numeric(Sys.time() - t0, units = "mins")))
bad <- character()
for (p in args) {
  ok <- requireNamespace(p, quietly = TRUE)
  cat(sprintf("INSTALL %-12s %s\n", p, if (ok) paste("ok", packageVersion(p)) else "FAILED"))
  if (!ok) bad <- c(bad, p)
}
for (p in bad) {
  f <- file.path(logs, paste0(p, ".out"))
  if (file.exists(f)) {
    cat(sprintf("\n----- %s (last 60 lines of %s)\n", p, f))
    writeLines(tail(readLines(f, warn = FALSE), 60))
  }
}
if (length(bad)) quit(status = 1)
