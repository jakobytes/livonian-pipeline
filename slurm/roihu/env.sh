# Common settings for the Roihu job scripts. Sourced by each *.sbatch file.
#
# Paths can be overridden by setting the variables in the environment
# before calling submit.sh (sbatch passes the environment on to the jobs).

set -eo pipefail

PROJECT=${SLURM_JOB_ACCOUNT:?run this inside a Slurm job submitted with -A}

# Tykky environments built from env-cpu.yml and env-gpu.yml.
# The CPU nodes are x86_64 and the GPU nodes aarch64, so each needs its own.
FILTER_ENV_DIR=${FILTER_ENV_DIR:-/projappl/$PROJECT}
case "$(uname -m)" in
  x86_64)  export PATH="$FILTER_ENV_DIR/filter-cpu-env/bin:$PATH" ;;
  aarch64) export PATH="$FILTER_ENV_DIR/filter-gpu-env/bin:$PATH" ;;
esac

# Intermediate and output files go to scratch; the raw data is read from
# the repository checkout (data/raw).
FILTER_SCRATCH=${FILTER_SCRATCH:-/scratch/$PROJECT/filter-pipeline}
POEM_SIM_JOBS=${POEM_SIM_JOBS:-4}
MAKE_VARS=(
  work_dir="$FILTER_SCRATCH/work"
  DATA_DIR="$FILTER_SCRATCH/output"
  POEM_SIM_JOBS="$POEM_SIM_JOBS"
)
mkdir -p "$FILTER_SCRATCH/work" "$FILTER_SCRATCH/output"

# With EMB_MODEL set, the similarity jobs compute the embedding-based
# tables (the emb_* targets in the Makefile) instead of the n-gram ones.
SIM=
if [ -n "$EMB_MODEL" ]; then
  MAKE_VARS+=(EMB_MODEL="$EMB_MODEL")
  SIM=emb_
fi

# Inputs produced by preprocess.sbatch, never to be remade by later jobs.
KEEP_INPUTS=(
  -o "$FILTER_SCRATCH/output/verses_cl.csv"
  -o "$FILTER_SCRATCH/work/verses_cl_by_length.csv"
)

cd "$SLURM_SUBMIT_DIR"
