#!/bin/bash
# Submit the pipeline on Roihu as a chain of dependent Slurm jobs:
#
#   preprocess (CPU) -+-> verse_sim (GPU) ---------> verse_clust (CPU)
#                     +-> poem_sim (GPU array) ----> poem_clust (CPU)
#
# With EMB_MODEL set, the similarities are computed from the verse
# embeddings of that model instead of character n-grams, preceded by
# an emb_vectors (CPU) job that prepares the embeddings.
#
# Usage (on either Roihu login node):
#   [EMB_MODEL=...] slurm/roihu/submit.sh project_XXXXXXX [--skip-preprocess]
#
# The number of poem_sim parts (= GPUs) is set by POEM_SIM_JOBS (default 4).

set -eo pipefail

account=${1:?usage: $0 project_XXXXXXX [--skip-preprocess]}
export POEM_SIM_JOBS=${POEM_SIM_JOBS:-4}

cd "$(dirname "$0")/../.."
mkdir -p logs

sb() { sbatch --parsable -A "$account" "$@"; }

dep=()
if [ "$2" != "--skip-preprocess" ]; then
  pre=$(sb slurm/roihu/preprocess.sbatch)
  dep=(--dependency=afterok:$pre)
  echo "preprocess:  $pre"
fi

if [ -n "$EMB_MODEL" ]; then
  ev=$(sb "${dep[@]}" slurm/roihu/emb_vectors.sbatch)
  dep=(--dependency=afterok:$ev)
  echo "emb_vectors: $ev ($EMB_MODEL)"
fi

vs=$(sb "${dep[@]}" slurm/roihu/verse_sim.sbatch)
vc=$(sb --dependency=afterok:$vs slurm/roihu/verse_clust.sbatch)
ps=$(sb "${dep[@]}" --array=0-$((POEM_SIM_JOBS-1)) slurm/roihu/poem_sim.sbatch)
pc=$(sb --dependency=afterok:$ps slurm/roihu/poem_clust.sbatch)

echo "verse_sim:   $vs"
echo "verse_clust: $vc"
echo "poem_sim:    $ps (array of $POEM_SIM_JOBS)"
echo "poem_clust:  $pc"
