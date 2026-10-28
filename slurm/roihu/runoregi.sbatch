#!/bin/bash
#SBATCH --job-name=filter-runoregi
#SBATCH --partition=small
#SBATCH --time=12:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=128G
#SBATCH --output=logs/%x-%j.out

# Builds the runoregi database tables as Parquet files.

source slurm/roihu/env.sh

# No -j: the rules extend shared key dictionaries (e.g. poems.idmap.csv).
make "${MAKE_VARS[@]}" "${KEEP_INPUTS[@]}" runoregi
