# reference: https://daniel-furman.github.io/Python-species-distribution-modeling/

import os
import geopandas as gpd
import glob
import numpy as np
import rasterio
from pyimpute import load_training_vector, load_targets, impute
from sklearn.ensemble import RandomForestClassifier
from sklearn.ensemble import ExtraTreesClassifier
from xgboost import XGBClassifier
from lightgbm import LGBMClassifier
from sklearn.linear_model import LogisticRegression
from sklearn import model_selection
from sklearn.neural_network import MLPClassifier


def impute_with_na(
    target_xs,
    model,
    raster_info,
    outdir,
    class_prob=True,
    certainty=True,
    na_value=-999,
):
    # Step 1: Identify and temporarily replace NA values with a sentinel value (-999)
    na_mask = np.isnan(target_xs)  # Mask where NA values are present
    target_xs_filled = np.copy(target_xs)
    target_xs_filled[na_mask] = na_value

    # Step 2: Perform the imputation with the filled data
    imputed_result = impute(
        target_xs_filled,
        model,
        raster_info,
        outdir=outdir,
        class_prob=class_prob,
        certainty=certainty,
    )

    # Step 3: Apply NA mask to each imputed file in the output directory
    for filename in os.listdir(outdir):
        if filename.endswith(".tif"):
            filepath = os.path.join(outdir, filename)
            with rasterio.open(filepath, "r+") as dst:
                # Read the existing data
                imputed_layer = dst.read(1).astype(float)  # Assuming single-band raster

                # Replace the sentinel value (-999) with NaN
                imputed_layer[imputed_layer == na_value] = np.nan

                # Write the modified data back to the same file
                dst.write(imputed_layer, 1)


def run_model(sp, future=False):
    # Create output directory
    os.makedirs(f"outputs/{sp}/", exist_ok=True)

    # Load shapefile
    shp_file = glob.glob(f"inputs/{sp}/*.shp")
    pa = gpd.GeoDataFrame.from_file(shp_file[0])

    # Load raster features
    clim_features_present = sorted(glob.glob("data/chelsa/climatology/resample/*.tif"))
    cover_features = sorted(glob.glob("data/cover/resample/*.tif"))
    cover_features = [file for file in cover_features if "_12.tif" not in file]
    elevation_feature = sorted(glob.glob("data/elevation/resample/*.tif"))

    raster_features_present = clim_features_present + cover_features + elevation_feature

    # Optionally load future climate data
    if future:
        clim_features_future1 = sorted(
            glob.glob("data/chelsa/cmip5/2041-2060/average/*.tif")
        )
        clim_features_future2 = sorted(
            glob.glob("data/chelsa/cmip5/2061-2080/average/*.tif")
        )
        raster_features_future1 = (
            clim_features_future1 + cover_features + elevation_feature
        )
        raster_features_future2 = (
            clim_features_future2 + cover_features + elevation_feature
        )

    # Load training data and targets
    train_xs, train_y = load_training_vector(
        pa, raster_features_present, response_field="CLASS"
    )
    # Create a boolean mask for rows without NA values
    mask = ~np.isnan(train_xs).any(axis=1)
    # Apply the mask to filter out rows with NA values
    cleaned_train_xs = train_xs[mask]
    cleaned_train_y = train_y[mask]

    target_xs_present, raster_info_present = load_targets(raster_features_present)

    if future:
        target_xs_future1, raster_info_future1 = load_targets(raster_features_future1)
        target_xs_future2, raster_info_future2 = load_targets(raster_features_future2)

    # Define classifiers
    CLASS_MAP = {
        "rf": RandomForestClassifier(
            n_estimators=100,
            max_depth=10,
            min_samples_split=5,
            min_samples_leaf=4,
            max_features="sqrt",
        ),
        "et": ExtraTreesClassifier(
            n_estimators=100,
            max_depth=10,
            min_samples_split=5,
            min_samples_leaf=4,
            max_features="sqrt",
        ),
        "xgb": XGBClassifier(reg_alpha=1.0, reg_lambda=1.0),
        "lgbm": LGBMClassifier(verbose=-1, lambda_l1=1.0, lambda_l2=1.0),
        "logreg": LogisticRegression(
            max_iter=1000, penalty="elasticnet", solver="saga", C=1.0, l1_ratio=0.5
        ),
        "mlp": MLPClassifier(alpha=0.1, max_iter=500),
    }

    # Model training, cross-validation, and spatial prediction
    for name, model in CLASS_MAP.items():
        # Cross-validation
        k = 5
        kf = model_selection.KFold(n_splits=k)
        accuracy_scores = model_selection.cross_val_score(
            model, cleaned_train_xs, cleaned_train_y, cv=kf, scoring="accuracy"
        )
        print(
            f"{name} {kf.get_n_splits()}-fold Cross Validation Accuracy: {accuracy_scores.mean() * 100:.2f} (+/- {accuracy_scores.std() * 100:.2f})"
        )

        # Save cross-validation metrics
        os.makedirs(f"outputs/{sp}/present/{name}-images", exist_ok=True)
        with open(
            f"outputs/{sp}/present/{name}-images/cross_validation_metrics.txt", "w"
        ) as file:
            file.write(
                f"{name} {kf.get_n_splits()}-fold Cross Validation Accuracy: {accuracy_scores.mean() * 100:.2f} (+/- {accuracy_scores.std() * 100:.2f})\n"
            )

        # Fit model and predict
        model.fit(cleaned_train_xs, cleaned_train_y)
        impute_with_na(
            target_xs_present,
            model,
            raster_info_present,
            outdir=f"outputs/{sp}/present/{name}-images",
            class_prob=True,
            certainty=True,
        )

        if future:
            impute_with_na(
                target_xs_future1,
                model,
                raster_info_future1,
                outdir=f"outputs/{sp}/future1/{name}-images",
                class_prob=True,
                certainty=True,
            )
            impute_with_na(
                target_xs_future2,
                model,
                raster_info_future2,
                outdir=f"outputs/{sp}/future2/{name}-images",
                class_prob=True,
                certainty=True,
            )


# Direct function call
run_model(sp="pd", future=True)
run_model(sp="zp", future=True)
