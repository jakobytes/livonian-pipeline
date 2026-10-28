# Slurm jobs for computing cluster

For CSC's Roihu, see [roihu/README.md](roihu/README.md). The scripts
below were written for Puhti, which has been retired.

This folder contains job scripts for running the pipeline on the
[Puhti](https://docs.csc.fi/computing/systems-puhti/) supercomputer.
For other systems, the resource specifications (e.g. partition names)
might need to be adjusted.

The jobs can be run as follows:
```
sbatch -A project_XXXXXXX JOB_FILE
```
where `XXXXXXX` is the CSC project number. Make sure to have the Conda
environment setup first (see the main README).

First run the job `preprocess.sbatch` and wait until it's completed.
Then, `poem_sim.sbatch` and `verse_sim.sbatch` can be run concurrently.

The scripts use the environment variable `$PROJSCRATCH` (containing path
to the project's scratch directory) and assume the existence of a
directory `$PROJSCRATCH/filter-data`, to which they output the results.

