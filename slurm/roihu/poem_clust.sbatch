#!/bin/bash
#SBATCH --job-name=filter-poem-clust
#SBATCH --partition=small
#SBATCH --time=04:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=64G
#SBATCH --output=logs/%x-%j.out

source slurm/roihu/env.sh

# Concatenates the parts computed by poem_sim.sbatch and clusters the poems.
make "${MAKE_VARS[@]}" "${KEEP_INPUTS[@]}" ${SIM}poem_clust
