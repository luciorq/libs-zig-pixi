# Smoke test of the R packages that link the zig-* libraries (DESIGN 9.2,
# M4; slice 2 adds gmp, Rmpfr, igraph, nloptr, units, gsl, RPostgres and
# the text stack's png, jpeg, tiff, webp, systemfonts, textshaping, ragg,
# xml2, and the data stack's hdf5r, ncdf4, RNetCDF; slice 3 protobuf's
# protolite and RProtoBuf): sf, terra, gdalraster, s2, gmp, Rmpfr, igraph,
# nloptr, units, gsl, RPostgres, png, jpeg, tiff, webp, systemfonts,
# textshaping, ragg, xml2, hdf5r, ncdf4, RNetCDF, protolite, RProtoBuf.
# RPostgres' query checks need a server: R_SMOKE_PG names one as libpq
# connection keywords (e.g. "host=127.0.0.1 port=5432 user=postgres
# dbname=postgres"); without it they are left out. Run it with the R that
# installed them:
#   Rscript tests/r/smoke.R [package ...]      (default: all of them)
# Each check prints one "SMOKE <name> PASS|FAIL|ERROR" line; the script
# exits with status 1 when any check is not PASS. First run: kappa win-64,
# 2026-11-22 (r-zig-pixi feat-zig-libs PLAN.md).
args <- commandArgs(trailingOnly = TRUE)
pkgs <- if (length(args)) args else c("sf", "terra", "gdalraster", "s2", "gmp", "Rmpfr", "igraph", "nloptr", "units", "gsl", "RPostgres",
                                         "png", "jpeg", "tiff", "webp", "systemfonts", "textshaping", "ragg", "xml2", "hdf5r", "ncdf4", "RNetCDF",
                                         "protolite", "RProtoBuf")

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

# slice 2 batch 2: zig-nlopt (nloptr), zig-udunits2 (units, through
# zig-expat)
if ("nloptr" %in% pkgs) {
  library(nloptr)
  rosen <- function(x) 100 * (x[2] - x[1]^2)^2 + (1 - x[1])^2
  grad <- function(x) c(-400 * x[1] * (x[2] - x[1]^2) - 2 * (1 - x[1]), 200 * (x[2] - x[1]^2))
  chk("nloptr: Rosenbrock, LBFGS", {
    r <- nloptr(c(-1.2, 1), rosen, grad, opts = list(algorithm = "NLOPT_LD_LBFGS", xtol_rel = 1e-10, maxeval = 1000))
    r$status > 0 && max(abs(r$solution - 1)) < 1e-4
  })
  chk("nloptr: Rosenbrock, Nelder-Mead", {
    r <- nloptr(c(-1.2, 1), rosen, opts = list(algorithm = "NLOPT_LN_NELDERMEAD", xtol_rel = 1e-10, maxeval = 5000))
    r$status > 0 && max(abs(r$solution - 1)) < 1e-3
  })
  chk("nloptr: StoGO (NLopt's C++ code)", {
    r <- nloptr(c(-1.2, 1), rosen, grad, lb = c(-2, -2), ub = c(2, 2),
                opts = list(algorithm = "NLOPT_GD_STOGO", xtol_rel = 1e-8, maxeval = 5000))
    r$status > 0 && max(abs(r$solution - 1)) < 1e-2
  })
}

if ("units" %in% pkgs) {
  library(units)
  chk("units: 2.5 km in m", {
    as.numeric(set_units(set_units(2.5, km), m)) == 2500
  })
  chk("units: derived units (km/h -> m/s)", {
    abs(as.numeric(set_units(set_units(36, km/h), m/s)) - 10) < 1e-12
  })
  chk("units: incompatible units are an error", {
    inherits(try(set_units(set_units(1, kg), m), silent = TRUE), "try-error")
  })
}

# slice 2 batch 3: zig-gsl (gsl: special functions, GSL's own CBLAS is
# linked but not called)
if ("gsl" %in% pkgs) {
  library(gsl)
  chk("gsl: bessel_J0(5)", {
    abs(bessel_J0(5) - (-0.17759677131433830)) < 1e-15
  })
  chk("gsl: gamma via lngamma, hyperg_1F1", {
    abs(exp(lngamma(5.5)) - gamma(5.5)) < 1e-10 &&
      abs(hyperg_1F1(1, 1, 2) - exp(2)) < 1e-12
  })
  chk("gsl: GSL error comes back as an R error or NaN", {
    v <- tryCatch(bessel_Kn(-1, 0), error = function(e) NaN, warning = function(w) NaN)
    is.nan(v) || is.infinite(v)
  })
}

# slice 2: zig-libpq (RPostgres, through zig-openssl)
if ("RPostgres" %in% pkgs) {
  library(DBI)
  chk("RPostgres: libpq 16.10 (PQlibVersion)", {
    RPostgres:::client_version() == 160010L
  })
  chk("RPostgres: a refused connection is an error", {
    !dbCanConnect(RPostgres::Postgres(), host = "127.0.0.1", port = 1L,
                  connect_timeout = 5L, sslmode = "disable")
  })
  pg <- Sys.getenv("R_SMOKE_PG")
  if (nzchar(pg)) {
    kv <- regmatches(pg, gregexpr("[^ =]+=[^ ]*", pg))[[1]]
    args <- setNames(as.list(sub("^[^=]+=", "", kv)), sub("=.*$", "", kv))
    con <- do.call(dbConnect, c(list(RPostgres::Postgres()), args))
    chk("RPostgres: query round trip (server)", {
      r <- dbGetQuery(con, "SELECT 1 + 1 AS two, 'zig'::text AS s, now() IS NOT NULL AS t")
      r$two == 2 && r$s == "zig" && isTRUE(r$t)
    })
    chk("RPostgres: write and read a table, bytea and numeric", {
      dbWriteTable(con, "zig_smoke", data.frame(x = c(1.5, 2.5), y = c("a", "b")), temporary = TRUE)
      sum(dbReadTable(con, "zig_smoke")$x) == 4 &&
        identical(dbGetQuery(con, "SELECT '\\x4f4b'::bytea AS b")$b[[1]], as.raw(c(0x4f, 0x4b)))
    })
    dbDisconnect(con)
  }
}

# slice 2 text stack (D122): libpng, libjpeg, libtiff (its codecs), libwebp,
# freetype, harfbuzz, fribidi
# a smooth image: red rises left to right, green and blue flat (lossy
# codecs blur sharp edges in chroma, so a striped image is no test)
img <- array(0, c(16, 32, 3))
img[, , 1] <- rep(seq(0, 1, length.out = 32), each = 16)
img[, , 2] <- 0.25
img[, , 3] <- 0.75
if ("png" %in% pkgs) {
  chk("png: write and read an RGB image", {
    f <- tempfile(fileext = ".png"); png::writePNG(img, f)
    max(abs(png::readPNG(f) - img)) < 1 / 255 + 1e-9
  })
}
if ("jpeg" %in% pkgs) {
  chk("jpeg: write and read (lossy, close)", {
    f <- tempfile(fileext = ".jpg"); jpeg::writeJPEG(img, f, quality = 0.95)
    r <- jpeg::readJPEG(f)
    identical(dim(r), dim(img)) && mean(abs(r - img)) < 0.02
  })
}
if ("tiff" %in% pkgs) {
  for (cmp in c("LZW", "deflate", "none")) local({
    cmp <- cmp
    chk(sprintf("tiff: write and read (%s)", cmp), {
      f <- tempfile(fileext = ".tif"); tiff::writeTIFF(img, f, compression = cmp)
      max(abs(tiff::readTIFF(f) - img)) < 1 / 255 + 1e-9
    })
  })
  chk("tiff: write and read (JPEG, close)", {
    f <- tempfile(fileext = ".tif"); tiff::writeTIFF(img, f, compression = "JPEG")
    mean(abs(tiff::readTIFF(f) - img)) < 0.03
  })
}
if ("webp" %in% pkgs) {
  chk("webp: write and read (lossy, close)", {
    a <- array(1, c(16, 32, 4)); a[, , 1:3] <- img
    f <- tempfile(fileext = ".webp"); webp::write_webp(a, f, quality = 100)
    r <- webp::read_webp(f)
    identical(dim(r), c(16L, 32L, 4L)) && mean(abs(r[, , 1:3] - img)) < 0.03
  })
}
if ("systemfonts" %in% pkgs) {
  chk("systemfonts: system fonts found (freetype)", {
    nrow(systemfonts::system_fonts()) > 0 && file.exists(systemfonts::match_fonts("sans")$path)
  })
}
if ("textshaping" %in% pkgs) {
  chk("textshaping: shape Latin text (harfbuzz)", {
    s <- textshaping::shape_text("Hello world")$shape
    nrow(s) == 11 && all(diff(s$x_offset) >= 0) && max(s$x_offset) > 0
  })
  chk("textshaping: right-to-left Hebrew (fribidi)", {
    s <- textshaping::shape_text("\u05e9\u05dc\u05d5\u05dd abc")$shape
    nrow(s) == 8 && all(s$index > 0)
  })
}
if ("ragg" %in% pkgs) {
  draw <- function() { plot(1:10, main = "zig-libs"); text(5, 5, "Hello \u05e9\u05dc\u05d5\u05dd", cex = 2) }
  chk("ragg: agg_png with text (freetype, libpng)", {
    f <- tempfile(fileext = ".png"); ragg::agg_png(f, 300, 200); draw(); dev.off()
    # reading it back needs png (in the default list); without it, its size
    if (requireNamespace("png", quietly = TRUE)) {
      r <- png::readPNG(f); identical(dim(r)[1:2], c(200L, 300L)) && min(r[, , 1:3]) < 0.5
    } else file.size(f) > 1000
  })
  chk("ragg: agg_tiff and agg_jpeg write files (libtiff, libjpeg)", {
    f1 <- tempfile(fileext = ".tif"); ragg::agg_tiff(f1, 300, 200, compression = "lzw"); draw(); dev.off()
    f2 <- tempfile(fileext = ".jpg"); ragg::agg_jpeg(f2, 300, 200); draw(); dev.off()
    file.size(f1) > 1000 && file.size(f2) > 1000
  })
  chk("ragg: agg_webp writes a file (libwebp)", {
    f <- tempfile(fileext = ".webp"); ragg::agg_webp(f, 300, 200); draw(); dev.off()
    file.size(f) > 100
  })
}

# slice 2 libxml2 (D125 B): zig-libxml2 with zig-libiconv, zlib and lzma
if ("xml2" %in% pkgs) {
  chk("xml2: parse and XPath (libxml2)", {
    d <- xml2::read_xml("<a><b n='1'>x</b><b n='2'>y</b></a>")
    identical(xml2::xml_text(xml2::xml_find_all(d, "//b[@n='2']")), "y")
  })
  chk("xml2: ISO-8859-1 document (built-in encoding)", {
    raw <- c(charToRaw("<?xml version='1.0' encoding='ISO-8859-1'?><a>caf"), as.raw(0xe9), charToRaw("</a>"))
    identical(xml2::xml_text(xml2::read_xml(raw)), "caf\u00e9")
  })
  chk("xml2: Shift_JIS document (iconv)", {
    raw <- c(charToRaw("<?xml version='1.0' encoding='Shift_JIS'?><a>"), as.raw(c(0x93, 0xfa, 0x96, 0x7b)), charToRaw("</a>"))
    identical(xml2::xml_text(xml2::read_xml(raw)), "\u65e5\u672c")
  })
  chk("xml2: gzip-compressed file (zlib)", {
    f <- tempfile(fileext = ".xml.gz"); con <- gzfile(f, "w"); writeLines("<a><b>gz</b></a>", con); close(con)
    identical(xml2::xml_text(xml2::read_xml(f)), "gz")
  })
}

# slice 2 data stack (D126 B, D127 C): zig-hdf5 with zlib and szip (libaec)
if ("hdf5r" %in% pkgs) {
  suppressPackageStartupMessages(library(hdf5r))
  m <- matrix(as.integer(seq_len(2400) %% 97), 40, 60)
  chk("hdf5r: HDF5 1.12 library", {
    v <- numeric_version(paste(h5version(verbose = FALSE), collapse = "."))
    v >= "1.12" && v < "1.13"
  })
  chk("hdf5r: chunked deflate dataset round trip (zlib)", {
    f <- tempfile(fileext = ".h5"); h <- H5File$new(f, mode = "w")
    h$create_dataset("d", m, chunk_dims = c(10, 10), gzip_level = 6); h$close_all()
    h <- H5File$new(f, mode = "r"); r <- h[["d"]][, ]; h$close_all(); identical(r, m)
  })
  chk("hdf5r: szip dataset round trip (libaec)", {
    # hdf5r 1.3.16's H5P set_szip() calls R_H5Pset_szip with one argument
    # of three, so the C entry point directly: options_mask
    # H5_SZIP_NN_OPTION_MASK (32), 16 pixels per block
    f <- tempfile(fileext = ".h5"); h <- H5File$new(f, mode = "w")
    sp <- H5P_DATASET_CREATE$new(); sp$set_chunk(c(10, 10))
    stopifnot(.Call("R_H5Pset_szip", sp$id, 32L, 16L, PACKAGE = "hdf5r")$return_val >= 0)
    h$create_dataset("s", m, dataset_create_pl = sp); h$close_all()
    h <- H5File$new(f, mode = "r"); r <- h[["s"]][, ]; h$close_all(); identical(r, m)
  })
}

# zig-netcdf (netCDF-4 through zig-hdf5, classic formats); DAP needs a
# server, so it is checked by hand (slice2 PLAN.md S2-F34)
if ("ncdf4" %in% pkgs) {
  chk("ncdf4: netCDF-4 compressed variable round trip (hdf5)", {
    f <- tempfile(fileext = ".nc")
    x <- ncdf4::ncdim_def("x", "m", 1:30); y <- ncdf4::ncdim_def("y", "m", 1:20)
    v <- ncdf4::ncvar_def("t", "K", list(x, y), -999, prec = "double", compression = 6)
    nc <- ncdf4::nc_create(f, v, force_v4 = TRUE)
    m <- outer(1:30, 1:20, function(i, j) i * 0.5 + j)
    ncdf4::ncvar_put(nc, v, m); ncdf4::ncatt_put(nc, 0, "title", "zig-libs"); ncdf4::nc_close(nc)
    nc <- ncdf4::nc_open(f); r <- ncdf4::ncvar_get(nc, "t"); a <- ncdf4::ncatt_get(nc, 0, "title")$value
    fmt <- nc$format; ncdf4::nc_close(nc)
    isTRUE(all.equal(r, m)) && identical(a, "zig-libs") && fmt == "NC_FORMAT_NETCDF4"
  })
}
if ("RNetCDF" %in% pkgs) {
  for (fmt in c("classic", "data64", "netcdf4")) local({
    fmt <- fmt
    chk(sprintf("RNetCDF: %s file round trip", fmt), {
      f <- tempfile(fileext = ".nc"); nc <- RNetCDF::create.nc(f, format = fmt)
      RNetCDF::dim.def.nc(nc, "n", 50)
      RNetCDF::var.def.nc(nc, "v", if (fmt == "classic") "NC_INT" else "NC_INT64", "n")
      x <- if (fmt == "classic") 1:50 else seq(1, 50) * 1e10
      RNetCDF::var.put.nc(nc, "v", x); RNetCDF::close.nc(nc)
      nc <- RNetCDF::open.nc(f); r <- RNetCDF::var.get.nc(nc, "v"); RNetCDF::close.nc(nc)
      isTRUE(all.equal(as.numeric(r), as.numeric(x)))
    })
  })
}
if ("protolite" %in% pkgs) {
  # protolite compiles its .proto files with zig-protobuf's protoc at
  # install time (-DUSENEWAPI), so a round trip checks protoc and
  # libprotobuf together
  chk("protolite: serialize_pb/unserialize_pb round trip", {
    x <- list(a = 1:3, b = "zig-libs", c = c(1.5, NA), d = list(e = TRUE))
    identical(protolite::unserialize_pb(protolite::serialize_pb(x)), x)
  })
}
if ("RProtoBuf" %in% pkgs) {
  # tutorial.Person: RProtoBuf's own addressbook.proto, read at load;
  # GOOGLE_PROTOBUF_VERSION of protobuf 29.5 is 5029005 (C++ 5.29.5)
  chk("RProtoBuf: libprotobuf 29.5 and a message round trip", {
    d <- RProtoBuf::P("tutorial.Person")
    p <- RProtoBuf::new(d, name = "zig", id = 42L, email = "z@example.org")
    q <- RProtoBuf::read(d, RProtoBuf::serialize(p, NULL))
    v <- RProtoBuf:::getProtobufLibVersion()
    if (q$name == "zig" && q$id == 42L && v == 5029005L) TRUE else c(q$name, q$id, v)
  })
}

cat("\nSUMMARY\n")
for (n in names(res)) cat(sprintf("%-48s %s\n", n, res[[n]]))
ok <- length(res) > 0 && all(res == "PASS")
cat("ALL_PASS:", ok, "\n")
if (!ok) quit(status = 1)
