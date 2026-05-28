import numpy as np
import xarray as xr
import os
import glob

# PATHS
RUNS_DIR = "/home/arya/Projects/Earth_System_Physics/final_project/run1"
RUN_FOLDERS = ["output"] + [f"output_s{i:02d}" for i in range(1, 12)]
OUTPUT_FILE_PATTERN = "IDEAL_ATM.190002*.nc"
OUTPUT_DIR = "./results"

# SIMULATION TIME-SLICE
SPINUP_DAYS   = 30
ANALYSIS_DAYS = 60

# Ranges of perturbed parameters
SIGS_MIN, SIGS_MAX = 0.05,  0.25
SIGD_MIN, SIGD_MAX = 0.01,  0.10

# [sigs_1, sigd_1, epmax_lnd_1, elcrit_lnd_1],...]
PARAM_NAMES  = ["sigs", "sigd"]
PARAM_LABELS = [r"$\sigma_s$", r"$\sigma_d$"]

# Extract vaues of the perturbed parameters 
PARAM = {}

for run_folder in RUN_FOLDERS:
    folder_path = os.path.join(RUNS_DIR, run_folder)
    files = glob.glob(os.path.join(folder_path, OUTPUT_FILE_PATTERN))
    for f in files:
        try:
            with xr.open_dataset(f) as ds:
                PARAM[run_folder] = [
                        ds.attrs["mit_fractional_precip_outside_cloud"],
                        ds.attrs["mit_fractional_area_unsaturated_downdraft"]]
        except Exception as e:
                print(f"Could not read {f}:{e}")

PARAM_VALUES = list(PARAM.values())

# Check perturbed values 
#print(PARAM_VALUES)

# VARIABLE NAMES
SCALAR_VARS = {
    "prc" : "Convective precipitation flux [kg m⁻² s⁻¹]",
    "pr" : "Precipitation flux [kg m⁻² s⁻¹]",
    "hfls" : "surface_upward_latent_heat_flux [W m⁻²]",
    "zmla" : "atmosphere_boundary_layer_thickness [m]",
    "scfwind" : "Near-Surface Wind Speed [m/s] "
    }

PROFILE_VARS = {
        "cl": "Cloud fractional cover [1]",
        "qrl" : "Longwave radiation heating rate [K s⁻¹]"
}

LEVEL_HPA = 500

# STATISTICS
ALPHA = 0.05
N_MEMBERS = 10
