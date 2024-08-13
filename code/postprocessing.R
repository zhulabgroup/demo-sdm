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

plot_maps <- function(path) {
  files <- list.files(path, full.names = T, pattern = ".tif", recursive = T)
  for (file in files) {
    ras <- terra::rast(file)
    var_name <- str_remove(basename(file), ".tif")
    p <- ras %>%
      as.data.frame(xy = T) %>%
      ggplot() +
      geom_tile(aes(x = x, y = y, fill = !!sym(names(ras)))) +
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
    for (model in c("rf", "et", "xgb", "lgbm", "logreg", "mlp")) {
      clip_to_area(
        path_in = str_c("outputs/", sp, "/", period, "/", model, "-images/"),
        path_area = str_c("inputs/", sp, "/"),
        path_out = str_c("outputs/", sp, "/", period, "/", model, "-images/")
      )

      plot_maps(path = str_c("outputs/", sp, "/", period, "/", model, "-images/"))
    }
  }
}

average_decision_tree <- function(path_in,
                                  path_out) {
  dir.create(path_out, showWarnings = F, recursive = T)
  files <- list.files(path_in, full.names = T, pattern = "probability_1.*.tif", recursive = T)
  files <- files[str_detect(files, "rf-|et-|xgb-|lgbm-")]

  # average all rasters
  ras_list <- terra::rast(files)
  ras_mean <- terra::mean(ras_list, na.rm = T)
  terra::writeRaster(ras_mean,
    file.path(path_out, "probability_mean.tif"),
    overwrite = TRUE
  )

  ras_stdev <- terra::stdev(ras_list, na.rm = T)
  terra::writeRaster(ras_stdev,
    file.path(path_out, "probability_stdev.tif"),
    overwrite = TRUE
  )
}

for (sp in c("pd", "zp")) {
  for (period in c("present", "future1", "future2")) {
    average_decision_tree(
      path_in = str_c("outputs/", sp, "/", period, "/"),
      path_out = str_c("outputs/", sp, "/", period, "/average/")
    )
  }
}

for (sp in c("pd", "zp")) {
  for (period in c("present", "future1", "future2")) {
    plot_maps(path = str_c("outputs/", sp, "/", period, "/average/"))
  }
}
