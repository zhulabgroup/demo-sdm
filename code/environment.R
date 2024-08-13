library(tidyverse)

read_elevation <- function(path = "data/elevation/") {
  # https://www.temis.nl/data/gmted2010/index.php
  dir.create(str_c(path, "tif/"), showWarnings = F, recursive = T)

  # read in hdf
  file <- list.files(path = path, pattern = ".nc$", full.names = TRUE)
  ras <- terra::rast(file)
  terra::writeRaster(ras$elevation,
    filename = str_c(path, "tif/elevation.tif"),
    overwrite = T
  )
}

read_elevation()

resample_raster <- function(path_in,
                            path_out,
                            deg = 0.5) {
  dir.create(path_out, showWarnings = F, recursive = T)

  files <- list.files(path = path_in, pattern = ".tif$", full.names = TRUE)

  extent_grid <- terra::ext(-180, 180, -90, 90)
  resolution <- deg
  grid_raster <- terra::rast(extent = extent_grid, res = resolution)
  terra::crs(grid_raster) <- "EPSG:4326"

  for (file in files) {
    ras <- terra::rast(file)
    ras_re <- terra::resample(ras, grid_raster, method = "near")
    terra::writeRaster(ras_re,
      file.path(path_out, basename(file)),
      overwrite = TRUE
    )

    print(file)
  }
}

resample_raster(
  path_in = "data/chelsa/climatology",
  path_out = "data/chelsa/climatology/resample/"
)

resample_raster(
  path_in = "data/chelsa/cmip5/2041-2060/",
  path_out = "data/chelsa/cmip5/2041-2060/resample/"
)

resample_raster(
  path_in = "data/chelsa/cmip5/2061-2080/",
  path_out = "data/chelsa/cmip5/2061-2080/resample/"
)

resample_raster(
  path_in = "data/cover/",
  path_out = "data/cover/resample/"
)

resample_raster(
  path_in = "data/elevation/tif/",
  path_out = "data/elevation/resample/"
)

average_model <- function(path_in,
                          path_out) {
  dir.create(path_out, showWarnings = FALSE)
  for (bioclim in 1:19) {
    files <- list.files(path_in, full.names = TRUE, pattern = str_c(".nc_", bioclim, "_.*\\.tif"))
    ras_list <- terra::rast(files)
    ras_list[ras_list == -32768] <- NA
    if (bioclim %in% 1:11) {
      ras_list <- ras_list / 10
    }
    # calculate mean
    ras_mean <- terra::mean(ras_list)
    terra::writeRaster(ras_mean,
      str_c(path_out, bioclim, ".tif"),
      overwrite = TRUE
    )
    print(bioclim)
  }
}

average_model(
  path_in = "data/chelsa/cmip5/2041-2060/resample/",
  path_out = "data/chelsa/cmip5/2041-2060/average/"
)

average_model(
  path_in = "data/chelsa/cmip5/2061-2080/resample/",
  path_out = "data/chelsa/cmip5/2061-2080/average/"
)
