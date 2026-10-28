#!/bin/bash
#SBATCH --job-name=filter-poem-sim
#SBATCH --partition=gpumedium
#SBATCH --gres=gpu:gh200:1
#SBATCH --time=12:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --output=logs/%x-%A_%a.out

# Array job: task i computes part i of POEM_SIM_JOBS (one GPU per part).
# Submit with --array=0-$((POEM_SIM_JOBS-1)), as done by submit.sh.

source slurm/roihu/env.sh

make "${MAKE_VARS[@]}" "${KEEP_INPUTS[@]}" \
  ${SIM}p_sim_part_$SLURM_ARRAY_TASK_ID
