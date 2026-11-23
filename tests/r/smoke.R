# Smoke test of the R packages that link the zig-* libraries (DESIGN 9.2,
# M4; slice 2 adds gmp, Rmpfr, igraph): sf, terra, gdalraster, s2, gmp,
# Rmpfr, igraph. Run it with the R that installed them:
#   Rscript tests/r/smoke.R [package ...]      (default: all of them)
# Each check prints one "SMOKE <name> PASS|FAIL|ERROR" line; the script
# exits with status 1 when any check is not PASS. First run: kappa win-64,
# 2026-11-22 (r-zig-pixi feat-zig-libs PLAN.md).
args <- commandArgs(trailingOnly = TRUE)
pkgs <- if (length(args)) args else c("sf", "terra", "gdalraster", "s2", "gmp", "Rmpfr", "igraph")

res <- character()
chk <- function(name, expr) {
  t0 <- Sys.time()
  r <- tryCatch({
    v <- force(expr)
    if (isTRUE(v)) "PASS" else paste("FAIL:", paste(format(v), collapse = " "))
  }, error = function(e) paste("ERROR:", conditionMessage(e)))
  cat(sprintf("SMOKE %-48s %s (%.2fs)\n", name, r,
              as.numeric(Sys.time() - t0, units = "secs")))
  res[[name]] <<- r
}
cat(R.version.string, "\n")
for (p in pkgs) cat(sprintf("pkg %s %s (%s)\n", p, packageVersion(p), find.package(p)))

if ("sf" %in% pkgs) {
  suppressPackageStartupMessages(library(sf))
  print(sf_extSoftVersion())
  nc <- NULL
  chk("sf: read Shapefile nc.shp (100 rows)", {
    nc <- st_read(system.file("shape/nc.shp", package = "sf"), quiet = TRUE)
    nrow(nc) == 100
  })
  gp <- file.path(tempdir(), "nc.gpkg")
  chk("sf: write+read GPKG", {
    st_write(nc, gp, quiet = TRUE, delete_dsn = TRUE)
    g <- st_read(gp, quiet = TRUE)
    nrow(g) == 100 && st_crs(g) == st_crs(nc)
  })
  ncp <- NULL
  chk("sf: st_transform 4267 -> 32119 (PROJ)", {
    ncp <- st_transform(nc, 32119)
    st_crs(ncp)$epsg == 32119 && abs(st_bbox(ncp)[["xmin"]] - 123829) < 1000
  })
  chk("sf: st_transform point 4326 -> 3857", {
    p <- st_transform(st_sfc(st_point(c(10, 50)), crs = 4326), 3857)
    abs(st_coordinates(p)[1, "X"] - 1113194.9) < 1
  })
  chk("sf: GEOS union+buffer+area", {
    u <- st_union(st_buffer(ncp[1:5, ], 1000))
    a <- as.numeric(st_area(u))
    is.finite(a) && a > sum(as.numeric(st_area(ncp[1:5, ])))
  })
  chk("sf: GEOS intersects", {
    m <- st_intersects(ncp[1:10, ], ncp)
    length(m) == 10 && all(lengths(m) >= 1)
  })
  chk("sf: s2 spherical area", {
    sf_use_s2(TRUE)
    a <- as.numeric(sum(st_area(nc)))
    a > 1.2e11 && a < 1.3e11
  })
}

if ("terra" %in% pkgs) {
  suppressPackageStartupMessages(library(terra))
  print(terra::libVersion("all"))
  # not libVersion("TBB"): terra lowercases the name before comparing it
  # with "TBB" and returns a data.frame (terra 1.9-60, R/gdal.R:81)
  chk("terra: built with TBB", isTRUE(terra:::.have_TBB()))
  chk("terra: read raster elev.tif", {
    r <- rast(system.file("ex/elev.tif", package = "terra"))
    all(dim(r) == c(90, 95, 1)) && is.finite(global(r, "mean", na.rm = TRUE)[1, 1])
  })
  chk("terra: project raster (PROJ)", {
    p <- project(rast(system.file("ex/elev.tif", package = "terra")), "EPSG:3857")
    grepl("Pseudo-Mercator|3857", crs(p))
  })
  chk("terra: read vector lux.shp", {
    nrow(vect(system.file("ex/lux.shp", package = "terra"))) == 12
  })
  # A TBB-parallel call: focal "median" (sum and max take sliding fast
  # paths that show no threading). Several threads show as CPU time well
  # above elapsed time; a speed comparison alone is noisy on CI runners.
  set.seed(1)
  big <- rast(nrows = 2000, ncols = 2000, vals = runif(2000 * 2000))
  w <- matrix(1, 9, 9)
  terraOptions(parallel = FALSE)
  s1 <- system.time(f1 <- focal(big, w, fun = "median"))
  terraOptions(parallel = TRUE, threads = 4)
  s4 <- system.time(f4 <- focal(big, w, fun = "median"))
  terraOptions(parallel = FALSE)
  cpu4 <- s4[["user.self"]] + s4[["sys.self"]]
  ratio <- cpu4 / max(s4[["elapsed"]], 1e-3)
  cat(sprintf("terra focal 2000x2000 9x9 median: serial %.2fs, threads=4 %.2fs elapsed %.2fs cpu, cpu/elapsed %.2f\n",
              s1[["elapsed"]], s4[["elapsed"]], cpu4, ratio))
  chk("terra: TBB focal parallel == serial", isTRUE(all.equal(values(f1), values(f4))))
  chk("terra: TBB focal uses several threads", ratio > 1.5)
}

if ("gdalraster" %in% pkgs) {
  suppressPackageStartupMessages(library(gdalraster))
  print(gdal_version())
  chk("gdalraster: GDALRaster storml_elev.tif", {
    ds <- new(GDALRaster, system.file("extdata/storml_elev.tif", package = "gdalraster"))
    d <- ds$dim()
    ds$close()
    length(d) == 3 && all(d > 0)
  })
  chk("gdalraster: srs_to_wkt + transform_xy (PROJ)", {
    w <- srs_to_wkt("EPSG:5070")
    x <- transform_xy(matrix(c(-120, 45), 1), "EPSG:4326", "EPSG:5070")
    nzchar(w) && all(is.finite(x))
  })
  chk("gdalraster: >= 100 GDAL drivers", nrow(gdal_formats()) >= 100)
}

if ("s2" %in% pkgs) {
  library(s2)
  chk("s2: s2_area", {
    a <- s2_area(as_s2_geography("POLYGON ((0 0, 1 0, 1 1, 0 1, 0 0))"))
    a > 1.2e10 && a < 1.3e10
  })
  chk("s2: s2_union", {
    s2_num_points(s2_union(as_s2_geography("POINT (0 0)"), as_s2_geography("POINT (1 1)"))) == 2
  })
  chk("s2: s2_buffer_cells", {
    s2_area(s2_buffer_cells(as_s2_geography("POINT (0 0)"), 1000)) > 0
  })
  chk("s2: s2_intersects + s2_distance", {
    s2_intersects(as_s2_geography("POLYGON ((0 0, 2 0, 2 2, 0 2, 0 0))"), as_s2_geography("POINT (1 1)")) &&
      s2_distance(as_s2_geography("POINT (0 0)"), as_s2_geography("POINT (0 1)")) > 1e5
  })
  chk("s2: countries union", {
    s2_area(s2_union_agg(s2_data_countries(c("France", "Germany", "Belgium")))) > 8e11
  })
}

# slice 2 batch 1: zig-gmp (gmp, Rmpfr, igraph), zig-mpfr (Rmpfr),
# zig-glpk (igraph's cluster_optimal, GLPK's exact MIP)
if ("gmp" %in% pkgs) {
  library(gmp)
  chk("gmp: factorialZ(30)", {
    as.character(factorialZ(30)) == "265252859812191058636308480000000"
  })
  chk("gmp: isprime(2^127 - 1)", {
    isprime(as.bigz(2)^127 - 1) > 0 && isprime(as.bigz(2)^127 + 1) == 0
  })
  chk("gmp: bigq 1/3 + 1/6", {
    as.character(as.bigq(1, 3) + as.bigq(1, 6)) == "1/2"
  })
}

if ("Rmpfr" %in% pkgs) {
  suppressPackageStartupMessages(library(Rmpfr))
  chk("Rmpfr: pi to 200 bits", {
    startsWith(formatMpfr(Const("pi", 200), digits = 50), "3.14159265358979323846264338327950288419716939937")
  })
  chk("Rmpfr: mpfr(1, 100) / 3", {
    x <- mpfr(1, 100) / 3
    getPrec(x) == 100 && abs(as.numeric(x * 3) - 1) < 1e-15
  })
}

if ("igraph" %in% pkgs) {
  suppressPackageStartupMessages(library(igraph))
  chk("igraph: ring vcount/ecount", {
    g <- make_ring(10)
    vcount(g) == 10 && ecount(g) == 10
  })
  chk("igraph: cluster_optimal (GLPK)", {
    # two triangles joined by one edge: the optimal partition is the two
    # triangles; cluster_optimal solves an integer program with GLPK
    g <- graph_from_literal(A - B - C - A, D - E - F - D, C - D)
    m <- membership(cluster_optimal(g))
    length(unique(m)) == 2 && m[["A"]] == m[["B"]] && m[["D"]] == m[["F"]] && m[["A"]] != m[["D"]]
  })
  chk("igraph: GraphML round trip (libxml2)", {
    f <- tempfile(fileext = ".graphml")
    write_graph(make_star(5), f, format = "graphml")
    g <- read_graph(f, format = "graphml")
    vcount(g) == 5 && ecount(g) == 4
  })
}

cat("\nSUMMARY\n")
for (n in names(res)) cat(sprintf("%-48s %s\n", n, res[[n]]))
ok <- length(res) > 0 && all(res == "PASS")
cat("ALL_PASS:", ok, "\n")
if (!ok) quit(status = 1)
