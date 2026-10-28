#!/bin/bash
#SBATCH --job-name=filter-emb-vectors
#SBATCH --partition=small
#SBATCH --time=04:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=64G
#SBATCH --output=logs/%x-%j.out

# Downloads the verse embeddings of EMB_MODEL and aligns them with the
# verses of the pipeline, for the emb_* similarity jobs.

source slurm/roihu/env.sh

make -j 2 "${MAKE_VARS[@]}" "${KEEP_INPUTS[@]}" emb_vectors
