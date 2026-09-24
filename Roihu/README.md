# Running on CSC Roihu

Files for running the pipeline on [Roihu](https://docs.csc.fi/computing/systems-roihu/).
Its CPU nodes are x86 and its GPU nodes ARM, so each stage has its own environment.

Build environments with Tykky on the matching login node:

- `roihu-cpu.csc.fi`: `env-cpu.yml`, then `make cpu-stage` or `sbatch Roihu/run_cpu.sh`
- `roihu-gpu.csc.fi`: `env.yml`, then `sbatch Roihu/run_gpu.sh`

Override paths with `work_dir=... DATA_DIR=...`.

Submit jobs from the repository root after `mkdir -p logs`; set the project at the top of each script.
