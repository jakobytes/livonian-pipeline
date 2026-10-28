# Slurm jobs for Roihu

Job scripts for running the pipeline on CSC's
[Roihu](https://docs.csc.fi/computing/systems-roihu/) supercomputer.

Roihu's CPU nodes are x86_64 (AMD Turin), while its GPU nodes are
aarch64 (NVIDIA GH200, ARM Grace CPU). The CPU and GPU jobs therefore
need separate environments.

## Environments

The environments are built with
[Tykky](https://docs.csc.fi/computing/containers/tykky/) from the
environment files in this directory, each on the login node of the
matching architecture:

```
# on roihu-gpu.csc.fi (the login node has no GPU, so the CUDA version
# needs to be given for conda to install the CUDA build of PyTorch)
module load tykky
CONDA_OVERRIDE_CUDA=12.9 \
  conda-containerize new --prefix /projappl/<project>/filter-gpu-env env-gpu.yml

# on roihu-cpu.csc.fi
module load tykky
conda-containerize new --prefix /projappl/<project>/filter-cpu-env env-cpu.yml
```

The job scripts pick the environment matching the node's architecture
(see `env.sh`). A different location can be given in `FILTER_ENV_DIR`.

## Running

From either login node, in the repository checkout (with the
submodules in `data/raw` initialized):

```
slurm/roihu/submit.sh project_XXXXXXX
```

This submits the following chain of jobs:

```
preprocess (CPU) -+-> verse_sim (GPU) ---------> verse_clust (CPU)
                  +-> poem_sim (GPU array) ----> poem_clust (CPU)
```

The GPU jobs only run the GPU computations (`shortsim-ngrcos` and
`poem_sim.py`); the clustering is done in separate CPU jobs.
The poem similarity is split into `POEM_SIM_JOBS` parts (default 4),
each computed on its own GPU, e.g.:

```
POEM_SIM_JOBS=8 slurm/roihu/submit.sh project_XXXXXXX
```

Use `--skip-preprocess` as the second argument to rerun only the
similarity jobs on existing preprocessed data.

### Embedding-based similarities

Setting `EMB_MODEL` computes the similarity and clustering tables from
precomputed verse embeddings
(<https://a3s.fi/filter-data/index.html>) instead of character n-grams:

```
EMB_MODEL=filter_p4_vb_v45_w45_m10_iso \
  slurm/roihu/submit.sh project_XXXXXXX --skip-preprocess
```

`EMB_MODEL` is the name of an embeddings file without the
`verse_embeddings_` prefix and `.parquet` suffix. An extra CPU job
downloads it and aligns it with the verses of the pipeline. The resulting
tables have the same names and formats as the n-gram ones, and are
written to `output/emb/<EMB_MODEL>/`. As there are no n-gram weightings,
`v_clust.tsv` only contains the clusterings 0 (default), 3 (tight)
and 4 (loose).

### Output

The intermediate and output files are written to
`/scratch/<project>/filter-pipeline/{work,output}` (can be changed by
setting `FILTER_SCRATCH`). The job logs are in `logs/`.
