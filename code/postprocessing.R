library(tidyverse)

clip_to_area <- function(path_in,
                         path_area,
                         path_out) {
  dir.create(path_out, showWarnings = F, recursive = T)
  files <- list.files(path_in, full.names = T, pattern = ".tif", recursive = T)

  # read land mask raster file
  area_mask <- terra::rast(
    list.files(path_area, pattern = "area.tif", full.names = T)
  )

  for (file in files) {
    ras <- terra::rast(file)
    ras_area <- terra::crop(ras, area_mask)
    ras_area <- terra::mask(ras_area, area_mask)
    terra::writeRaster(ras_area,
      file.path(path_out, basename(file)),
      overwrite = TRUE
    )
    print(file)
  }
}

plot_maps <- function(path = "outputs/pd/present/xgb-images/") {
  files <- list.files(path, full.names = T, pattern = ".tif", recursive = T)
  for (file in files) {
    ras <- terra::rast(file)
    var_name <- str_remove(basename(file), ".tif")
    p <- ras %>%
      as.data.frame(xy = T) %>%
      ggplot() +
      geom_tile(aes(x = x, y = y, fill = !!sym(var_name))) +
      scale_fill_gradient(
        low = "white",
        high = "darkgreen",
        na.value = "grey",
        limits = c(0, 1)
      ) +
      theme_minimal() +
      labs(
        x = "Longitude",
        y = "Latitude",
        fill = str_to_title(str_replace_all(var_name, "_", " "))
      )

    # save plot as pdf
    ggsave(str_c(path, var_name, ".pdf"), p,
      width = 10, height = 6.18
    )
  }
}

for (sp in c("pd", "zp")) {
  for (period in c("present", "future1", "future2")) {
    for (model in c("xgb", "lgbm")) {
      clip_to_area(
        path_in = str_c("outputs/", sp, "/", period, "/", model, "-images/"),
        path_area = str_c("inputs/", sp, "/"),
        path_out = str_c("outputs/", sp, "/", period, "/", model, "-images/")
      )

      plot_maps(path = str_c("outputs/", sp, "/", period, "/", model, "-images/"))
    }
  }
}
