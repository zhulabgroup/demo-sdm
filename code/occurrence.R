library(tidyverse)

# obtain occurrence records from GBIF
get_occ_data <- function(sp, path_land = "data/mask/", deg = 0.5) {
  dir.create(str_c("inputs/", sp), showWarnings = F, recursive = T)
  if (sp == "pd") {
    full_name <- "Prionailurus bengalensis"
  }
  if (sp == "zp") {
    full_name <- "Zamia prasina"
  }

  df_raw <- rgbif::occ_data(taxonKey = name_backbone(name = full_name, rank = "species") %>%
    pull(speciesKey), hasCoordinate = T, hasGeospatialIssue = F, limit = 1000000)

  if (sp == "pd") {
    df_raw$data <- df_raw$data %>%
      filter(decimalLongitude > 50)
  }
  if (sp == "zp") {
    df_raw$data <- df_raw$data %>%
      filter(decimalLongitude < 0)
  }
  write_csv(
    df_raw$data,
    str_c("inputs/", sp, "/occ_raw.csv")
  )

  datasetCounts <- df_raw$data %>%
    count(datasetKey, sort = TRUE)
  write.table(datasetCounts,
    str_c("inputs/", sp, "/derivedDatasetCounts.txt"),
    col.names = FALSE, row.names = FALSE, sep = ","
  )

  # get pseudo-absence
  # land mask
  land <- sf::st_read(list.files(path_land, pattern = ".shp", full.names = T))

  # Create a raster from the land mask
  extent_grid <- terra::ext(-180, 180, -90, 90)
  resolution <- deg
  grid_raster <- terra::rast(extent = extent_grid, res = resolution)
  terra::crs(grid_raster) <- "EPSG:4326"
  terra::values(grid_raster) <- 1

  land_raster <- terra::mask(grid_raster, land, touches = F)

  # Define study area
  local_extent <- terra::ext(
    df_raw$data$decimalLongitude %>% min() - df_raw$data$decimalLongitude %>% range() %>% diff() %>% `/`(2),
    df_raw$data$decimalLongitude %>% max() + df_raw$data$decimalLongitude %>% range() %>% diff() %>% `/`(2),
    df_raw$data$decimalLatitude %>% min() - df_raw$data$decimalLatitude %>% range() %>% diff() %>% `/`(2),
    df_raw$data$decimalLatitude %>% max() + df_raw$data$decimalLatitude %>% range() %>% diff() %>% `/`(2)
  )

  # Clip land mask to study area
  land_raster <- terra::crop(land_raster, local_extent)
  terra::writeRaster(land_raster,
    str_c("inputs/", sp, "/area.tif"),
    overwrite = TRUE
  )

  df_ab <- generate_land_points(num_points = df_raw$data %>% nrow(), land_raster)
  df_pa <- bind_rows(
    df_raw$data %>%
      select(decimalLongitude, decimalLatitude) %>%
      mutate(status = 1),
    df_ab %>%
      mutate(status = 0)
  )
  write_csv(
    df_pa,
    str_c("inputs/", sp, "/occ_pa.csv")
  )

  p <- df_pa %>%
    ggplot() +
    geom_tile(
      data = land_raster %>% as.data.frame(xy = T),
      aes(x = x, y = y, fill = "land"), alpha = 0.5, show.legend = F
    ) +
    geom_point(aes(decimalLongitude, decimalLatitude, pch = as.character(status)),
      col = "darkgreen", alpha = 0.5
    ) +
    scale_shape_manual(values = c("0" = 1, "1" = 19)) +
    scale_fill_manual(values = c("land" = "white")) +
    theme_minimal() +
    labs(
      x = "Longitude",
      y = "Latitude",
      shape = "Status"
    )

  # save plot as pdf
  ggsave(str_c("inputs/", sp, "/occ_pa.pdf"), p,
    width = 10, height = 6.18,
    device = cairo_pdf()
  )

  sf_pa <- df_pa %>%
    rename(CLASS = status) %>%
    sf::st_as_sf(coords = c("decimalLongitude", "decimalLatitude"), crs = 4326, remove = T) %>%
    sf::st_set_geometry("geometry")
  sf::st_write(sf_pa,
    str_c("inputs/", sp, "/occ_pa.shp"),
    append = F
  )
}

# Function to generate random points on land
generate_land_points <- function(num_points, land_mask) {
  land_mask <- raster::raster(land_mask)
  df_points <- dismo::randomPoints(land_mask, num_points) %>%
    as_tibble() %>%
    rename(decimalLongitude = x, decimalLatitude = y)

  return(df_points)
}

get_occ_data(sp = "pd")
get_occ_data(sp = "zp")

distance_to_center <- function(path = "inputs/pd/", deg = 1) {
  # Read the data
  df_occ <- read_csv(list.files(path, "_pa.csv", full.names = TRUE))

  centroid <- df_occ %>%
    filter(status == 1) %>%
    summarise(
      lon = median(decimalLongitude),
      lat = median(decimalLatitude)
    )
  # make it a spatial point
  centroid <- terra::vect(cbind(centroid$lon, centroid$lat), crs = "EPSG:4326")

  extent_grid <- terra::ext(-180, 180, -90, 90)
  resolution <- deg
  grid_raster <- terra::rast(extent = extent_grid, res = resolution)
  terra::crs(grid_raster) <- "EPSG:4326"

  # Calculate the distance to the centroid
  dist <- terra::distance(grid_raster, centroid)

  dist <- dist / 1000000000

  terra::writeRaster(dist,
    file.path(path, "distance_to_center.tif"),
    overwrite = TRUE
  )
}

# distance_to_center(path = "inputs/pd/", deg = 1)
# distance_to_center(path = "inputs/zp/", deg = 1)
