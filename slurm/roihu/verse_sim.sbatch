#!/bin/bash
#SBATCH --job-name=filter-verse-sim
#SBATCH --partition=gpumedium
#SBATCH --gres=gpu:gh200:1
#SBATCH --time=04:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --output=logs/%x-%j.out

source slurm/roihu/env.sh

# The three n-gram weightings run side by side on the same GPU.
make -j 3 "${MAKE_VARS[@]}" "${KEEP_INPUTS[@]}" ${SIM}verse_sim
