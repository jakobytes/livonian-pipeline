#!/bin/bash
#SBATCH --job-name=preprocess
#SBATCH --time=1:00:00
#SBATCH --mem-per-cpu=16G
#SBATCH --cpus-per-task=1
#SBATCH --partition=small
#SBATCH --ntasks=1

srun -D .. env DATA_DIR=csvs \
	make combined

