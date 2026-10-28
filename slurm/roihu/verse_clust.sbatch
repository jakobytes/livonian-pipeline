#!/bin/bash
#SBATCH --job-name=filter-verse-clust
#SBATCH --partition=small
#SBATCH --time=12:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=6
#SBATCH --mem=96G
#SBATCH --output=logs/%x-%j.out

source slurm/roihu/env.sh

# Clustering is CPU-only; the six clusterings run in parallel.
make -j "$SLURM_CPUS_PER_TASK" "${MAKE_VARS[@]}" "${KEEP_INPUTS[@]}" \
  ${SIM}verse_clust
