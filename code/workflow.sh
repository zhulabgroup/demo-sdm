#!/bin/bash

Rscript -e "source('code/environment.R')"
Rscript -e "source('code/occurrence.R')"
python3 code/model.py
Rscript -e "source('code/postprocessing.R')"

