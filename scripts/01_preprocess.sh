#!/usr/bin/env bash
set -euo pipefail

# Root directory containing output files
RUNDIR="${RUNDIR:-/home/arya/Projects/Earth_System_Physics/final_project/run1}"

# Output directory for processed files
OUTDIR="${OUTDIR:-/home/arya/Projects/Earth_System_Physics/numerical_data_analysis/emanuel_stochastic_analysis/data}"

# Variables for the analysis
VARS="pr,prc,hfls,prw,huss,tas"

# Variable pairs examined within each run.
PAIRS=(
  "pr prw"      # precipitation - column water vapour  (precip pickup)
  "prc hfls"    # convective precip - surface latent heat flux (moisture supply)
  "pr huss"     # precipitation - near-surface humidity (downdraft re-evaporation)
)

# No detrend for now just 60 days for analysis (change to 1 to activate)
DETREND="${DETREND:-0}"

# Number of spin-up timesteps to discard (30x6)
SPINUP="${SPINUP:-120}"

# Number of ensemble members for each run type
N_BASE="${N_BASE:-6}"
N_STOCH="${N_STOCH:-6}"

mkdir -p "$OUTDIR"

# helper for the to 2 digits used
zpad2 () { printf '%02d' "$1"; }

# helper to collect and merge all monthly files 
prep_member () {
  local srcdir="$1" tag="$2"
  local merged="$OUTDIR/${tag}_merged.nc"
  local clean="$OUTDIR/${tag}_clean.nc"

  # Collect SRF files and abort if none found
  local srffiles=( "$srcdir"/IDEAL_SRF.*.nc )
  if [ ! -e "${srffiles[0]}" ]; then
    echo "!! No surface files found in $srcdir — skipping $tag"
    return 1
  fi

  echo ">> [$tag] merging ${#srffiles[@]} surface files from $srcdir"
  cdo -s mergetime "${srffiles[@]}" "$merged"

  echo ">> [$tag] selecting variables: $VARS"
  cdo -s selname,"$VARS" "$merged" "$OUTDIR/${tag}_sel.nc"
  rm -f "$merged"

  if [ "$SPINUP" -gt 0 ]; then
    local ntot; ntot=$(cdo -s ntime "$OUTDIR/${tag}_sel.nc")
    echo ">> [$tag] discarding first $SPINUP of $ntot timesteps (spin-up)"
    cdo -s seltimestep,$((SPINUP+1))/"$ntot" "$OUTDIR/${tag}_sel.nc" "$clean"
    rm -f "$OUTDIR/${tag}_sel.nc"
  else
    mv "$OUTDIR/${tag}_sel.nc" "$clean"
  fi
  echo "   -> $clean  (n = $(cdo -s ntime "$clean") timesteps)"
}

# helper to do the domain-mean time series
fldmean_member () {
  local tag="$1"
  echo ">> [$tag] building domain-mean time series (fldmean)"
  cdo -s fldmean "$OUTDIR/${tag}_clean.nc" "$OUTDIR/${tag}_fldmean.nc"
}

# helper for the per-grid-point temporal correlation + covariance map
maps_member () {
  local tag="$1"
  local clean="$OUTDIR/${tag}_clean.nc"
  for p in "${PAIRS[@]}"; do
    set -- $p; local X="$1" Y="$2"
    local xs="$OUTDIR/${tag}_${X}.nc"  ys="$OUTDIR/${tag}_${Y}.nc"
    cdo -s selname,"$X" "$clean" "$xs"
    cdo -s selname,"$Y" "$clean" "$ys"
    if [ "$DETREND" -eq 1 ]; then
      cdo -s detrend "$xs" "${xs%.nc}_dt.nc"; mv "${xs%.nc}_dt.nc" "$xs"
      cdo -s detrend "$ys" "${ys%.nc}_dt.nc"; mv "${ys%.nc}_dt.nc" "$ys"
    fi
    echo ">> [$tag] map: corr & cov of ($X , $Y)"
    cdo -s timcor   "$xs" "$ys" "$OUTDIR/${tag}_cor_${X}_${Y}.nc"
    cdo -s timcovar "$xs" "$ys" "$OUTDIR/${tag}_cov_${X}_${Y}.nc"
    rm -f "$xs" "$ys"
  done
}

# helper for the ensemble mean for both ensembles
ensemble_mean () {
  local runtag="$1" nmembers="$2"

  echo
  echo "=== Computing ensemble mean for: $runtag (${nmembers} members) ==="

  # fldmean ensemble mean
  local fldmean_files=()
  for i in $(seq 1 "$nmembers"); do
    local tag="${runtag}_$(zpad2 "$i")"
    fldmean_files+=( "$OUTDIR/${tag}_fldmean.nc" )
  done
  cdo -s ensmean "${fldmean_files[@]}" "$OUTDIR/${runtag}_ensmean_fldmean.nc"
  echo "   -> ${runtag}_ensmean_fldmean.nc"

  # correlation-covariance map ensemble mean
  for p in "${PAIRS[@]}"; do
    set -- $p; local X="$1" Y="$2"
    local cor_files=() cov_files=()
    for i in $(seq 1 "$nmembers"); do
      local tag="${runtag}_$(zpad2 "$i")"
      cor_files+=( "$OUTDIR/${tag}_cor_${X}_${Y}.nc" )
      cov_files+=( "$OUTDIR/${tag}_cov_${X}_${Y}.nc" )
    done
    cdo -s ensmean "${cor_files[@]}" "$OUTDIR/${runtag}_ensmean_cor_${X}_${Y}.nc"
    cdo -s ensmean "${cov_files[@]}" "$OUTDIR/${runtag}_ensmean_cov_${X}_${Y}.nc"
    echo "   -> ${runtag}_ensmean_cor_${X}_${Y}.nc  /  _cov_"
  done
}

# Iteration over all base members
echo " Processing BASE run members (output_01 ... output_$(zpad2 $N_BASE))"
for i in $(seq 1 "$N_BASE"); do
  idx=$(zpad2 "$i")
  srcdir="${RUNDIR}/output_${idx}"
  tag="base_${idx}"
  if [ -d "$srcdir" ]; then
    prep_member    "$srcdir" "$tag"
    fldmean_member "$tag"
    maps_member    "$tag"
  else
    echo "!! Directory $srcdir not found — skipping member $i"
  fi
done
ensemble_mean "base" "$N_BASE"

# Iteration over stochastic members (output_s01 ... output_sNN)
echo " Processing STOCHASTIC run members (output_s01 ... output_s$(zpad2 $N_STOCH))"
for i in $(seq 1 "$N_STOCH"); do
  idx=$(zpad2 "$i")
  srcdir="${RUNDIR}/output_s${idx}"
  tag="stoch_${idx}"
  if [ -d "$srcdir" ]; then
    prep_member    "$srcdir" "$tag"
    fldmean_member "$tag"
    maps_member    "$tag"
  else
    echo "!! Directory $srcdir not found — skipping member $i"
  fi
done
ensemble_mean "stoch" "$N_STOCH"

# Summary
echo
echo "DONE. Analysis-ready files in: $OUTDIR/"
echo
echo "  Per-member files:"
echo "    {base,stoch}_NN_fldmean.nc         domain-mean time series"
echo "    {base,stoch}_NN_cor_X_Y.nc         per-grid-point correlation map"
echo "    {base,stoch}_NN_cov_X_Y.nc         per-grid-point covariance map"
echo
echo "  Ensemble-mean files (for the CDA4 t-test / comparison):"
echo "    {base,stoch}_ensmean_fldmean.nc"
echo "    {base,stoch}_ensmean_cor_X_Y.nc"
echo "    {base,stoch}_ensmean_cov_X_Y.nc"
