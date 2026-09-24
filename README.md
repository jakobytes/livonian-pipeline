# FILTER pipeline

This repository contains a set of scripts for creating the corpus and
database used in the [FILTER project][1].
The corpus is a compilation of five folk poetry collections, of which
at the moment two are public and three non-public.
The pipeline produces a set of tables in CSV format that is stored in
[hsci-r/filter-data][2].

## Installation and running

After cloning this repository, initialize the Git submodules for the
source data using the command:
	git submodule update --init --recursive

Further, install the Python dependencies. The preferred way of doing it
is through Anaconda (conda-forge) - use the environment file `Roihu/env.yml`
on a machine with an NVIDIA GPU.`Roihu/env-cpu.yml`can be used to run the preprocessing on any PC. For CSC
computing clusters, it is recommended to use
[Tykky][3]; see
[`Roihu/`][4] for instructions on the Roihu supercomputer.

The different steps of the pipeline are called using GNU Make. The
environment variable `DATA_DIR` should be set to the path of the output
directory (which will contain the resulting CSV files). For example to
call the preprocessing, execute:
	DATA_DIR=/path/to/filter-data make combined

The whole pipeline runs in two stages: `make cpu-stage` (preprocessing)
and `make gpu-stage` (similarity computation).

## Steps

### Sources and preprocessing

Execute `make combined` to run the preprocessing step.

The corpus consists of five collections, which are linked as submodules in
`data/raw`:
* [Suomen Kansan Vanhat Runot (SKVR)][5] (public)
* [Eesti Regilaulude Andmebaas (ERAB)][6] (public)
* [Julkaisemattomat Runot (JR)][7] (private)
* [Kirjalliset Runot (KR)][8] (private)
* [Livonian folk songs (VLDL)][9] (private)

The private repositories are planned to be published, but currently
the pipeline can also be executed without them.

A description of the format of the source files can be found [here][10].

### Similarity computation

Execute `make gpu-stage` (or `make verse_sim` and `make poem_sim` separately)
to compute verse and poem similarities and clusterings. A GPU is used by
default.

## Copyright note

The code published in this repository is licensed under the MIT license.

For the folk poetry materials linked as submodules, see the information
in their repositories.

[1]:	https://blogs.helsinki.fi/filter-project/
[2]:	https://github.com/hsci-r/filter-data
[3]:	https://docs.csc.fi/computing/containers/tykky/
[4]:	./Roihu/README.md
[5]:	https://github.com/sks190/SKVR
[6]:	https://github.com/rahvaluule/erab
[7]:	https://github.com/sks190/jr
[8]:	https://github.com/sks190/kr_FILTER
[9]:	https://github.com/jakobytes/livonian-corpus
[10]:	./data/raw/README.md