#!/bin/bash
# CPU stage: parsing, cleaning and combining tables.
# Submit from the repository root on roihu-cpu.csc.fi:  sbatch Roihu/run_cpu.sh
#SBATCH --job-name=filter-cpu
#SBATCH --account=project_2020187
#SBATCH --partition=small
#SBATCH --time=04:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --output=logs/%x-%j.out

set -eo pipefail
PROJECT=project_2020187
S=/scratch/$PROJECT/livonian

export PATH="/projappl/$PROJECT/filter-cpu-env/bin:$PATH"
cd "$SLURM_SUBMIT_DIR"

make -j "$SLURM_CPUS_PER_TASK" cpu-stage work_dir=$S/work DATA_DIR=$S/output
