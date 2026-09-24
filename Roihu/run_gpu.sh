#!/bin/bash
# GPU stage: verse and poem similarity + clustering on one GH200.
# Submit from the repository root on roihu-gpu.csc.fi:  sbatch Roihu/run_gpu.sh
#SBATCH --job-name=filter-gpu
#SBATCH --account=project_2020187
#SBATCH --partition=gpumedium
#SBATCH --time=24:00:00
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1 --cpus-per-task=72
#SBATCH --gres=gpu:gh200:1
#SBATCH --output=logs/%x-%j.out

set -eo pipefail
PROJECT=project_2020187
S=/scratch/$PROJECT/livonian

export PATH="/projappl/$PROJECT/filter-gpu-env/bin:$PATH"
export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
cd "$SLURM_SUBMIT_DIR"

nvidia-smi --query-gpu=name,memory.total --format=csv
python3 -c "import torch, faiss; assert torch.cuda.is_available(); print('torch', torch.__version__, '| faiss GPUs:', faiss.get_num_gpus())"

make gpu-stage work_dir=$S/work DATA_DIR=$S/output
