#!/bin/bash
# Submit the pipeline on Roihu as a chain of dependent Slurm jobs:
#
#   preprocess (CPU) -+-> verse_sim (GPU) ---------> verse_clust (CPU) -+-> runoregi (CPU)
#                     +-> poem_sim (GPU array) ----> poem_clust (CPU) --+
#
# With EMB_MODEL set, the similarities are computed from the verse
# embeddings of that model instead of character n-grams, preceded by
# an emb_vectors (CPU) job that prepares the embeddings. The runoregi
# tables then contain the n-gram similarities computed by an earlier run,
# plus the verse clusterings of the embeddings.
#
# Usage (on either Roihu login node):
#   [EMB_MODEL=...] slurm/roihu/submit.sh project_XXXXXXX [--skip-preprocess]
#
# The number of poem_sim parts (= GPUs) is set by POEM_SIM_JOBS (default 4).
# With AFTER set to a job ID, the chain starts only after that job has
# completed successfully (e.g. the runoregi job of an n-gram run).

set -eo pipefail

account=${1:?usage: $0 project_XXXXXXX [--skip-preprocess]}
export POEM_SIM_JOBS=${POEM_SIM_JOBS:-4}

cd "$(dirname "$0")/../.."
mkdir -p logs

sb() { sbatch --parsable -A "$account" "$@"; }

dep=()
if [ -n "$AFTER" ]; then
  dep=(--dependency=afterok:$AFTER)
fi
if [ "$2" != "--skip-preprocess" ]; then
  pre=$(sb "${dep[@]}" slurm/roihu/preprocess.sbatch)
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
rg=$(sb --dependency=afterok:$vc:$pc slurm/roihu/runoregi.sbatch)

echo "verse_sim:   $vs"
echo "verse_clust: $vc"
echo "poem_sim:    $ps (array of $POEM_SIM_JOBS)"
echo "poem_clust:  $pc"
echo "runoregi:    $rg"
