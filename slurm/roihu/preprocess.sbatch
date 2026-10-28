#!/bin/bash
#SBATCH --job-name=filter-preprocess
#SBATCH --partition=small
#SBATCH --time=04:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --output=logs/%x-%j.out

source slurm/roihu/env.sh

# Besides the combined tables, also build the inputs of the GPU jobs here,
# so that the concurrently running GPU jobs do not race to create them.
make -j "$SLURM_CPUS_PER_TASK" "${MAKE_VARS[@]}" \
  combined \
  "$FILTER_SCRATCH/work/verse_sim/verses_cl.list.txt" \
  "$FILTER_SCRATCH/work/verses_cl_by_length.csv"
