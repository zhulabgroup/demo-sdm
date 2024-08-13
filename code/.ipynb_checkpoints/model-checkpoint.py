import os 
import geopandas as gpd
import glob
from pyimpute import load_training_vector, load_targets, impute
from xgboost import XGBClassifier
from lightgbm import LGBMClassifier
from sklearn import model_selection

def run_model(sp, future=False):
    # Create output directory
    os.makedirs(f"outputs/{sp}/", exist_ok=True)

    # Load shapefile
    shp_file = glob.glob(f'inputs/{sp}/*.shp')
    pa = gpd.GeoDataFrame.from_file(shp_file[0])

    # Load raster features
    clim_features_present = sorted(glob.glob('data/chelsa/climatology/resample/*.tif'))
    cover_features = sorted(glob.glob('data/cover/resample/*.tif'))
    cover_features = [file for file in cover_features if '_12.tif' not in file]

    raster_features_present = clim_features_present + cover_features
    
    # Optionally load future climate data
    if future:
        clim_features_future1 = sorted(glob.glob('data/chelsa/cmip5/2041-2060/average/*.tif'))
        clim_features_future2 = sorted(glob.glob('data/chelsa/cmip5/2061-2080/average/*.tif'))
        raster_features_future1 = clim_features_future1 + cover_features
        raster_features_future2 = clim_features_future2 + cover_features

    # Load training data and targets
    train_xs_present, train_y = load_training_vector(pa, raster_features_present, response_field='CLASS')
    target_xs_present, raster_info_present = load_targets(raster_features_present)
    
    if future:
        target_xs_future1, raster_info_future1 = load_targets(raster_features_future1)
        target_xs_future2, raster_info_future2 = load_targets(raster_features_future2)

    # Define classifiers
    CLASS_MAP = {
        'xgb': XGBClassifier(reg_alpha=1.0, reg_lambda=1.0),
        'lgbm': LGBMClassifier(verbose=-1, lambda_l1=1.0, lambda_l2=1.0)
    }

    # Model training, cross-validation, and spatial prediction
    for name, model in CLASS_MAP.items():
        # Cross-validation
        k = 5
        kf = model_selection.KFold(n_splits=k)
        accuracy_scores = model_selection.cross_val_score(model, train_xs_present, train_y, cv=kf, scoring='accuracy')
        print(f"{name} {kf.get_n_splits()}-fold Cross Validation Accuracy: {accuracy_scores.mean() * 100:.2f} (+/- {accuracy_scores.std() * 200:.2f})")
        
        # Save cross-validation metrics
        os.makedirs(f"outputs/{sp}/present/{name}-images", exist_ok=True)
        with open(f"outputs/{sp}/present/{name}-images/cross_validation_metrics.txt", 'w') as file:
            file.write(f"{name} {kf.get_n_splits()}-fold Cross Validation Accuracy: {accuracy_scores.mean() * 100:.2f} (+/- {accuracy_scores.std() * 100:.2f})\n")
        
        # Fit model and predict
        model.fit(train_xs_present, train_y)
        impute(target_xs_present, model, raster_info_present, outdir=f"outputs/{sp}/present/{name}-images", class_prob=True, certainty=True)
        
        if future:
            impute(target_xs_future1, model, raster_info_future1, outdir=f"outputs/{sp}/future1/{name}-images", class_prob=True, certainty=True)
            impute(target_xs_future2, model, raster_info_future2, outdir=f"outputs/{sp}/future2/{name}-images", class_prob=True, certainty=True)

# Direct function call
run_model(sp="pd", future=True)
run_model(sp="zp", future=True)