# --- Roihu-specific settings -------------------------------------------------
# Fail a recipe if any command in a pipeline fails (not only the last one),
# and delete half-written targets on error or when a Slurm job hits its
# time limit, so that `make` never mistakes a truncated file for a finished one.
SHELL := /bin/bash
.SHELLFLAGS := -eo pipefail -c
.DELETE_ON_ERROR:

# Directories can be overridden on the command line or from the environment,
# e.g. make raw_dir=/scratch/<project>/filter/raw work_dir=... DATA_DIR=...
raw_dir ?= data/raw
work_dir ?= data/work
DATA_DIR := $(if $(DATA_DIR),$(DATA_DIR),data/output)

python = python3

# GPU switch for shortsim-ngrcos and poem_sim.py. Set GPU_FLAG= to run on CPU.
GPU_FLAG ?= -g

# Number of parts the poem similarity computation is split into
# (e.g. one per GPU in a Slurm array job, see slurm/roihu).
POEM_SIM_JOBS ?= 1

.PHONY: preprocess skvr erab jr kr vldl combined cpu-stage gpu-stage

# --- Stages ------------------------------------------------------------------
# cpu-stage: parsing, cleaning, combining (single-threaded tools; run with -j)
# gpu-stage: similarity computation (FAISS / PyTorch) and clustering
cpu-stage: preprocess combined

gpu-stage: verse_sim verse_clust poem_clust

preprocess: skvr erab jr kr vldl

skvr: \
  $(work_dir)/skvr/collectors.csv \
  $(work_dir)/skvr/verses.csv \
  $(work_dir)/skvr/word_occ.csv

erab: \
  $(work_dir)/erab/verses.csv \
  $(work_dir)/erab/collectors.csv \
  $(work_dir)/erab/places.csv \
  $(work_dir)/erab/word_occ.csv

jr: \
  $(work_dir)/jr/verses.csv \
  $(work_dir)/jr/word_occ.csv

kr: \
  $(work_dir)/kr/collectors.csv \
  $(work_dir)/kr/verses.csv \
  $(work_dir)/kr/places.csv \
  $(work_dir)/kr/poem_collector.csv \
  $(work_dir)/kr/poem_year.csv \
  $(work_dir)/kr/poem_place.csv \
  $(work_dir)/kr/poem_types.csv \
  $(work_dir)/kr/types.csv \
  $(work_dir)/kr/word_occ.csv

vldl: \
  $(work_dir)/vldl/verses.csv \
  $(work_dir)/vldl/meta.csv \
  $(work_dir)/vldl/poems.csv \
  $(work_dir)/vldl/raw_meta.csv \
  $(work_dir)/vldl/refs.csv \
  $(work_dir)/vldl/collectors.csv \
  $(work_dir)/vldl/places.csv \
  $(work_dir)/vldl/poem_place.csv \
  $(work_dir)/vldl/poem_collector.csv \
  $(work_dir)/vldl/poem_year.csv

###################################################################
# PREPROCESSING
###################################################################

$(work_dir)/skvr/verses.csv:
	mkdir -p $(work_dir)/skvr
	$(python) code/convert_skvr.py \
      -d $(work_dir)/skvr \
      --places-file $(raw_dir)/skvr/places.csv \
      --xml-types-file $(raw_dir)/skvr/tyyppiluettelo.xml \
      --json-types-file $(raw_dir)/skvr/themetree.json \
      --poem-types-file $(raw_dir)/skvr/viitteet_180221.txt \
	  $(raw_dir)/skvr/skvr_*.xml

$(work_dir)/erab/verses.csv:
	mkdir -p $(work_dir)/erab
	$(python) code/convert_erab.py \
	  -i $(raw_dir)/erab/csv -p erab_ -d $(work_dir)/erab  \
	  $(raw_dir)/erab/xml/*.xml

$(work_dir)/jr/verses.csv:
	mkdir -p $(work_dir)/jr
	$(python) code/convert_jr.py \
	  -d $(work_dir)/jr $(raw_dir)/jr/*.xml

# For now, let all tables depend on the verses table, as they are processed
# together. In the future, we might break up the preprocessing scripts so
# that some parts are preprocessed independently of others.

$(work_dir)/skvr/meta.csv:           $(work_dir)/skvr/verses.csv
$(work_dir)/skvr/places.csv:         $(work_dir)/skvr/verses.csv
$(work_dir)/skvr/poems.csv:          $(work_dir)/skvr/verses.csv
$(work_dir)/skvr/poem_types.csv:     $(work_dir)/skvr/verses.csv
$(work_dir)/skvr/raw_meta.csv:       $(work_dir)/skvr/verses.csv
$(work_dir)/skvr/refs.csv:           $(work_dir)/skvr/verses.csv
$(work_dir)/skvr/types.csv:          $(work_dir)/skvr/verses.csv
$(work_dir)/skvr/xmltypes.csv:       $(work_dir)/skvr/verses.csv

$(work_dir)/skvr/collectors.csv: $(raw_dir)/skvr/collectors.csv
	mkdir -p $(work_dir)/skvr
	csvcut -c 1,2 $< | sed '1s/.*/collector_id,collector_name/;' > $@

$(work_dir)/skvr/poem_place.csv: $(work_dir)/skvr/meta.csv
	csvcut -c poem_id,place_id $< > $@

$(work_dir)/skvr/poem_collector.csv: $(work_dir)/skvr/meta.csv
	csvcut -c poem_id,collector_id $< > $@

$(work_dir)/skvr/poem_year.csv: $(work_dir)/skvr/meta.csv
	csvcut -c poem_id,year $< > $@

$(work_dir)/erab/collectors.csv:     $(work_dir)/erab/verses.csv
$(work_dir)/erab/genres.csv:         $(work_dir)/erab/verses.csv
$(work_dir)/erab/places.csv:         $(work_dir)/erab/verses.csv
$(work_dir)/erab/poems.csv:          $(work_dir)/erab/verses.csv
$(work_dir)/erab/poem_collector.csv: $(work_dir)/erab/verses.csv
$(work_dir)/erab/poem_place.csv:     $(work_dir)/erab/verses.csv
$(work_dir)/erab/poem_types.csv:     $(work_dir)/erab/verses.csv
$(work_dir)/erab/poem_year.csv:      $(work_dir)/erab/verses.csv
$(work_dir)/erab/raw_meta.csv:       $(work_dir)/erab/verses.csv
$(work_dir)/erab/refs.csv:           $(work_dir)/erab/verses.csv
$(work_dir)/erab/types.csv:          $(work_dir)/erab/verses.csv

$(work_dir)/jr/raw_meta.csv:       $(work_dir)/jr/verses.csv
$(work_dir)/jr/refs.csv:           $(work_dir)/jr/verses.csv
$(work_dir)/jr/poems.csv:          $(work_dir)/jr/verses.csv
$(work_dir)/jr/poem_place.csv:     $(work_dir)/jr/verses.csv
$(work_dir)/jr/poem_collector.csv: $(work_dir)/jr/verses.csv
$(work_dir)/jr/poem_year.csv:      $(work_dir)/jr/verses.csv

$(work_dir)/kr/verses.csv:
	mkdir -p $(work_dir)/kr
	$(python) code/convert_skvr.py -p '' -c kr \
      -d $(work_dir)/kr \
	  $(raw_dir)/kr/*.xml $(raw_dir)/kr/kanteletar/*.xml

$(work_dir)/vldl/verses.csv:
	mkdir -p $(work_dir)/vldl
	$(python) code/convert_vldl.py \
      -d $(work_dir)/vldl \
	  $(raw_dir)/vldl/Volkslieder*.xml

$(work_dir)/kr/meta.csv:     $(work_dir)/kr/verses.csv
$(work_dir)/kr/poems.csv:    $(work_dir)/kr/verses.csv
$(work_dir)/kr/raw_meta.csv: $(work_dir)/kr/verses.csv
$(work_dir)/kr/refs.csv:     $(work_dir)/kr/verses.csv
$(work_dir)/vldl/meta.csv:     $(work_dir)/vldl/verses.csv
$(work_dir)/vldl/poems.csv:    $(work_dir)/vldl/verses.csv
$(work_dir)/vldl/raw_meta.csv: $(work_dir)/vldl/verses.csv
$(work_dir)/vldl/refs.csv:    $(work_dir)/vldl/verses.csv

$(work_dir)/vldl/poem_place.csv: $(work_dir)/vldl/meta.csv
	csvcut -c poem_id,place_id $< | csvgrep -c place_id -r '^.+$$' > $@

$(work_dir)/vldl/poem_collector.csv: $(work_dir)/vldl/meta.csv
	csvcut -c poem_id,collector_id $< | csvgrep -c collector_id -r '^.+$$' > $@

$(work_dir)/vldl/poem_year.csv: $(work_dir)/vldl/meta.csv
	csvcut -c poem_id,year $< | csvgrep -c year -r '^.+$$' > $@

# Copy rules: the raw file is a prerequisite only when it exists ($(wildcard)),
# so editing it triggers a rebuild, while a missing file still yields a header-only table.
$(work_dir)/kr/collectors.csv: $(wildcard $(raw_dir)/kr/collectors.csv)
	mkdir -p $(work_dir)/kr
	( [ -f "$(raw_dir)/kr/collectors.csv" ] \
	  && cp $(raw_dir)/kr/collectors.csv $@ ) \
	|| ( echo "collector_id,collector_name" > $@ )

$(work_dir)/vldl/collectors.csv: $(wildcard $(raw_dir)/vldl/collectors.csv)
	mkdir -p $(work_dir)/vldl
	( [ -f "$(raw_dir)/vldl/collectors.csv" ] \
	  && cp $(raw_dir)/vldl/collectors.csv $@ ) \
	|| ( echo "collector_id,collector_name" > $@ )

$(work_dir)/kr/poem_place.csv: $(work_dir)/kr/meta.csv
	csvcut -c poem_id,place_id $< | csvgrep -c place_id -r '^.+$$' > $@

$(work_dir)/kr/poem_collector.csv: $(work_dir)/kr/meta.csv
	csvcut -c poem_id,collector_id $< | csvgrep -c collector_id -r '^.+$$' > $@

$(work_dir)/kr/poem_types.csv: $(wildcard $(raw_dir)/kr/kanteletar/poem_category.csv)
	mkdir -p $(work_dir)/kr
	( [ -f "$(raw_dir)/kr/kanteletar/poem_category.csv" ] \
	  && cp $(raw_dir)/kr/kanteletar/poem_category.csv $@ ) \
	|| ( echo "poem_id,type_id,type_is_minor" > $@ )

$(work_dir)/kr/poem_year.csv: $(work_dir)/kr/meta.csv
	csvcut -c poem_id,year $< | csvgrep -c year -r '^.+$$' > $@

$(work_dir)/kr/places.csv: $(wildcard $(raw_dir)/kr/places.csv)
	mkdir -p $(work_dir)/kr
	( [ -f "$(raw_dir)/kr/places.csv" ] \
	  && cp $(raw_dir)/kr/places.csv $@ ) \
	|| ( echo "place_id,place_name,place_type,place_parent_id" > $@ )

$(work_dir)/vldl/places.csv: $(wildcard $(raw_dir)/vldl/places.csv)
	mkdir -p $(work_dir)/vldl
	( [ -f "$(raw_dir)/vldl/places.csv" ] \
	  && cp $(raw_dir)/vldl/places.csv $@ ) \
	|| ( echo "place_id,place_name,place_type,place_parent_id" > $@ )

$(work_dir)/kr/types.csv: $(wildcard $(raw_dir)/kr/kanteletar/categories.csv)
	mkdir -p $(work_dir)/kr
	( [ -f "$(raw_dir)/kr/kanteletar/categories.csv" ] \
	  && cp $(raw_dir)/kr/kanteletar/categories.csv $@ ) \
	|| ( echo "type_id,type_name,type_description,type_parent_id" > $@ )

# Verse cleaning
$(work_dir)/%/verses_cl.csv: $(work_dir)/%/verses.csv
	csvgrep -c verse_type -r "V" $< \
	| csvcut -c poem_id,pos,text \
	| $(python) code/clean_verses.py -c text > $@

# Tokenization of the cleaned verses table: just split on word boundaries.
$(work_dir)/%/word_occ.csv: $(work_dir)/%/verses_cl.csv
	awk -F, 'NR == 1 { print "poem_id,pos,word_pos,text"; }'\
	' NR > 1 { gsub(" +", " ", $$3);'\
	'         split($$3, a, " ");'\
	'         for (i in a) { print $$1","$$2","i","a[i]; } }'\
	  $< > $@

###################################################################
# COMBINED TABLES
###################################################################

# In the standard case, the combined tables are just concatenations
# of the tables for the individual subcorpora (using csvstack).
# Exceptions to this rule should be very rare and small.

# TODO provide for the possibility that the private repositories are empty
# (making a version using just the public data)

combined: \
  $(DATA_DIR)/areas.geojson \
  $(DATA_DIR)/collectors.csv \
  $(DATA_DIR)/counties.geojson \
  $(DATA_DIR)/places.csv \
  $(DATA_DIR)/poems.csv \
  $(DATA_DIR)/poem_collector.csv \
  $(DATA_DIR)/poem_duplicates.csv \
  $(DATA_DIR)/poem_place.csv \
  $(DATA_DIR)/poem_year.csv \
  $(DATA_DIR)/poem_types.csv \
  $(DATA_DIR)/polygon_to_place.csv \
  $(DATA_DIR)/raw_meta.csv \
  $(DATA_DIR)/refs.csv \
  $(DATA_DIR)/types.csv \
  $(DATA_DIR)/verses.csv \
  $(DATA_DIR)/verses_cl.csv \
  $(DATA_DIR)/word_occ.csv

$(DATA_DIR)/areas.geojson: $(raw_dir)/areas.geojson
	mkdir -p $(DATA_DIR)
	cp $< $@

$(DATA_DIR)/collectors.csv: \
  $(work_dir)/skvr/collectors.csv \
  $(work_dir)/erab/collectors.csv \
  $(work_dir)/kr/collectors.csv \
  $(work_dir)/vldl/collectors.csv
	mkdir -p $(DATA_DIR)
	csvstack $^ > $@

$(DATA_DIR)/counties.geojson: \
  $(raw_dir)/areas.geojson \
  $(raw_dir)/polygon_to_place.csv \
  $(DATA_DIR)/places.csv
	$(python) code/compute_county_polygons.py -G 10 -H 1000000 \
	  --areas-file $(raw_dir)/areas.geojson \
	  --polygon-to-place-file $(raw_dir)/polygon_to_place.csv \
	  --places-file $(DATA_DIR)/places.csv > $@

$(DATA_DIR)/places.csv: \
  $(work_dir)/skvr/places.csv \
  $(work_dir)/erab/places.csv \
  $(work_dir)/kr/places.csv \
  $(work_dir)/vldl/places.csv
	mkdir -p $(DATA_DIR)
	csvstack $^ > $@

$(DATA_DIR)/poems.csv: \
  $(work_dir)/skvr/poems.csv \
  $(work_dir)/erab/poems.csv \
  $(work_dir)/jr/poems.csv \
  $(work_dir)/kr/poems.csv \
  $(work_dir)/vldl/poems.csv
	mkdir -p $(DATA_DIR)
	csvstack $^ > $@

$(DATA_DIR)/poem_collector.csv: \
  $(work_dir)/skvr/poem_collector.csv \
  $(work_dir)/erab/poem_collector.csv \
  $(work_dir)/jr/poem_collector.csv \
  $(work_dir)/kr/poem_collector.csv \
  $(work_dir)/vldl/poem_collector.csv
	mkdir -p $(DATA_DIR)
	csvstack $^ > $@

$(DATA_DIR)/poem_duplicates.csv: \
  $(raw_dir)/skvr_poem_duplicates.csv
	mkdir -p $(DATA_DIR)
	cp $< $@

$(DATA_DIR)/poem_place.csv: \
  $(work_dir)/skvr/poem_place.csv \
  $(work_dir)/erab/poem_place.csv \
  $(work_dir)/jr/poem_place.csv \
  $(work_dir)/kr/poem_place.csv \
  $(work_dir)/vldl/poem_place.csv
	mkdir -p $(DATA_DIR)
	csvstack $^ > $@

$(DATA_DIR)/poem_types.csv: \
  $(work_dir)/skvr/poem_types.csv \
  $(work_dir)/erab/poem_types.csv \
  $(work_dir)/kr/poem_types.csv
	mkdir -p $(DATA_DIR)
	csvstack $^ > $@

$(DATA_DIR)/poem_year.csv: \
  $(work_dir)/skvr/poem_year.csv \
  $(work_dir)/erab/poem_year.csv \
  $(work_dir)/jr/poem_year.csv \
  $(work_dir)/kr/poem_year.csv \
  $(work_dir)/vldl/poem_year.csv
	mkdir -p $(DATA_DIR)
	csvstack $^ > $@

$(DATA_DIR)/polygon_to_place.csv: \
  $(raw_dir)/polygon_to_place.csv \
  $(DATA_DIR)/counties.geojson
	cp $< $@
	jq -r '.features[] | [.properties.id, .properties.place_id ] | @tsv'\
	    $(DATA_DIR)/counties.geojson \
	| sed 's/$$/\t1/' | csvformat -t -U 3 >> $@
	jq -r '.features[] | [.properties.id,'\
	'                    ( .properties.parish_place_ids | join(",") ) ] | @tsv'\
	    $(DATA_DIR)/counties.geojson \
	| awk '{ gsub(",", "\n"$$1",", $$2); print $$1","$$2; }' \
	| sed 's/$$/,0/' >> $@

$(DATA_DIR)/raw_meta.csv: \
  $(work_dir)/skvr/raw_meta.csv \
  $(work_dir)/erab/raw_meta.csv \
  $(work_dir)/jr/raw_meta.csv \
  $(work_dir)/kr/raw_meta.csv \
  $(work_dir)/vldl/raw_meta.csv
	mkdir -p $(DATA_DIR)
	csvstack $^ > $@

$(DATA_DIR)/refs.csv: \
  $(work_dir)/skvr/refs.csv \
  $(work_dir)/erab/refs.csv \
  $(work_dir)/jr/refs.csv \
  $(work_dir)/kr/refs.csv \
  $(work_dir)/vldl/refs.csv
	mkdir -p $(DATA_DIR)
	csvstack $^ > $@

$(DATA_DIR)/runoregi_pages.tsv: $(raw_dir)/runoregi_pages.json
	mkdir -p $(DATA_DIR)
	jq -r '.[] | [.view, .position, .title, (.helptext | join("\n")),'\
	'             (.content | join("\n"))] | @tsv' $< > $@

# Here we only keep columns that are present in all subcorpora.
# (`type_comparison` is only present in SKVR)
$(DATA_DIR)/types.csv: \
  $(work_dir)/skvr/types.csv \
  $(work_dir)/erab/types.csv \
  $(work_dir)/kr/types.csv
	mkdir -p $(DATA_DIR)
	csvstack $^ \
	| csvcut -c type_id,type_name,type_description,type_parent_id > $@
	$(python) code/add_type_links.py $@ -t 0.7

$(DATA_DIR)/verses.csv: \
  $(work_dir)/skvr/verses.csv \
  $(work_dir)/erab/verses.csv \
  $(work_dir)/jr/verses.csv \
  $(work_dir)/kr/verses.csv \
  $(work_dir)/vldl/verses.csv
	mkdir -p $(DATA_DIR)
	csvstack $^ > $@

$(DATA_DIR)/verses_cl.csv: \
  $(work_dir)/skvr/verses_cl.csv \
  $(work_dir)/erab/verses_cl.csv \
  $(work_dir)/jr/verses_cl.csv \
  $(work_dir)/kr/verses_cl.csv \
  $(work_dir)/vldl/verses_cl.csv
	mkdir -p $(DATA_DIR)
	csvstack $^ > $@

$(DATA_DIR)/word_occ.csv: \
  $(work_dir)/skvr/word_occ.csv \
  $(work_dir)/erab/word_occ.csv \
  $(work_dir)/jr/word_occ.csv \
  $(work_dir)/kr/word_occ.csv \
  $(work_dir)/vldl/word_occ.csv
	mkdir -p $(DATA_DIR)
	csvstack $^ > $@

###################################################################
# VERSE SIMILARITY AND CLUSTERING
###################################################################

$(work_dir)/verse_sim/verses_cl.list.txt: $(DATA_DIR)/verses_cl.csv
	mkdir -p $(work_dir)/verse_sim
	csvcut -c text $< | tail -n +2 | sort -u | sed '/^\s*$$/d' > $@

$(DATA_DIR)/v_sim.tsv: $(work_dir)/verse_sim/verses_cl.list.txt
	shortsim-ngrcos -t 0.75 $(GPU_FLAG) -p -d 450 < $< > $@

$(work_dir)/v_sim.sqrt.tsv: $(work_dir)/verse_sim/verses_cl.list.txt
	shortsim-ngrcos -w sqrt -t 0.75 $(GPU_FLAG) -p -d 450 < $< > $@

$(work_dir)/v_sim.binary.tsv: $(work_dir)/verse_sim/verses_cl.list.txt
	shortsim-ngrcos -w binary -t 0.75 $(GPU_FLAG) -p -d 450 < $< > $@

$(work_dir)/verse_sim/v_clust.default.tsv: \
  $(work_dir)/verse_sim/verses_cl.list.txt \
  $(DATA_DIR)/v_sim.tsv
	echo \
	| cat $(work_dir)/verse_sim/verses_cl.list.txt - $(DATA_DIR)/v_sim.tsv \
	| shortsim-cluster -s 0.8 > $@

$(work_dir)/verse_sim/v_clust.sqrt.tsv: \
  $(work_dir)/verse_sim/verses_cl.list.txt \
  $(work_dir)/v_sim.sqrt.tsv
	echo \
	| cat $(work_dir)/verse_sim/verses_cl.list.txt - $(work_dir)/v_sim.sqrt.tsv \
	| shortsim-cluster -s 0.8 > $@

$(work_dir)/verse_sim/v_clust.binary.tsv: \
  $(work_dir)/verse_sim/verses_cl.list.txt \
  $(work_dir)/v_sim.binary.tsv
	echo \
	| cat $(work_dir)/verse_sim/verses_cl.list.txt - $(work_dir)/v_sim.binary.tsv \
	| shortsim-cluster -s 0.8 > $@

$(work_dir)/verse_sim/v_clust.tight.tsv: \
  $(work_dir)/verse_sim/verses_cl.list.txt \
  $(DATA_DIR)/v_sim.tsv
	echo \
	| cat $(work_dir)/verse_sim/verses_cl.list.txt - $(DATA_DIR)/v_sim.tsv \
	| shortsim-cluster -s 0.85 > $@

$(work_dir)/verse_sim/v_clust.loose.tsv: \
  $(work_dir)/verse_sim/verses_cl.list.txt \
  $(DATA_DIR)/v_sim.tsv
	echo \
	| cat $(work_dir)/verse_sim/verses_cl.list.txt - $(DATA_DIR)/v_sim.tsv \
	| shortsim-cluster -s 0.75 > $@

$(work_dir)/verse_sim/v_clust.tight-binary.tsv: \
  $(work_dir)/verse_sim/verses_cl.list.txt \
  $(work_dir)/v_sim.binary.tsv
	echo \
	| cat $(work_dir)/verse_sim/verses_cl.list.txt - $(work_dir)/v_sim.binary.tsv \
	| shortsim-cluster -s 0.85 > $@

$(DATA_DIR)/v_clust.tsv: \
  $(work_dir)/verse_sim/v_clust.default.tsv \
  $(work_dir)/verse_sim/v_clust.sqrt.tsv \
  $(work_dir)/verse_sim/v_clust.binary.tsv \
  $(work_dir)/verse_sim/v_clust.tight.tsv \
  $(work_dir)/verse_sim/v_clust.loose.tsv \
  $(work_dir)/verse_sim/v_clust.tight-binary.tsv
	sed 's/^/0\t/' $(work_dir)/verse_sim/v_clust.default.tsv > $@
	sed 's/^/1\t/' $(work_dir)/verse_sim/v_clust.sqrt.tsv >> $@
	sed 's/^/2\t/' $(work_dir)/verse_sim/v_clust.binary.tsv >> $@
	sed 's/^/3\t/' $(work_dir)/verse_sim/v_clust.tight.tsv >> $@
	sed 's/^/4\t/' $(work_dir)/verse_sim/v_clust.loose.tsv >> $@
	sed 's/^/5\t/' $(work_dir)/verse_sim/v_clust.tight-binary.tsv >> $@

.PHONY: verse_sim verse_clust

verse_sim: \
  $(DATA_DIR)/v_sim.tsv \
  $(work_dir)/v_sim.sqrt.tsv \
  $(work_dir)/v_sim.binary.tsv

verse_clust: $(DATA_DIR)/v_clust.tsv $(DATA_DIR)/v_clusterings.csv

$(DATA_DIR)/v_clusterings.csv:
	mkdir -p $(DATA_DIR)
	echo 'clustering_id,name,description' > $@
	echo '0,default,' >> $@
	echo '1,sqrt,"sqrt weighting"' >> $@
	echo '2,binary,"binary weighting"' >> $@
	echo '3,tight,"threshold = 0.85"' >> $@
	echo '4,loose,"threshold = 0.75"' >> $@
	echo '5,tight-binary,"threshold = 0.85, binary weighting"' >> $@

###################################################################
# POEMS SIMILARITY AND CLUSTERING
###################################################################

# Before similarity computation, sort the poems from longest to shortest.
# This is done for optimization purposes: the poem_sim script works
# faster this way.
$(work_dir)/verses_cl_by_length.csv: $(DATA_DIR)/verses_cl.csv
	$(python) code/sort_poems_by_length.py < $< > $@

# The computation is split into $(POEM_SIM_JOBS) parts, which can be
# computed independently (e.g. in parallel on several GPUs) and are then
# concatenated. The parts are stored in a directory named after the number
# of parts, so that parts from runs with different splits are never mixed.
p_sim_parts_dir = $(work_dir)/p_sim/$(POEM_SIM_JOBS)
p_sim_parts = $(foreach i,$(shell seq 0 $$(($(POEM_SIM_JOBS)-1))),\
                $(p_sim_parts_dir)/part_$(i).csv)

$(p_sim_parts_dir)/part_%.csv: $(work_dir)/verses_cl_by_length.csv
	mkdir -p $(p_sim_parts_dir)
	$(python) code/poem_sim.py -t 0.5 -p -r $(GPU_FLAG) -d 450 -i $< -o $@ \
	  -j $* -J $(POEM_SIM_JOBS) \
	  --sim-raw-thr 1 --sim-onesided-thr 0.1 --sim-sym-thr 0 \
	  -L DEBUG --logfile $(p_sim_parts_dir)/part_$*.log

$(DATA_DIR)/p_sim.csv: $(p_sim_parts)
	head -n 1 $< > $@
	for f in $^; do tail -n +2 $$f; done >> $@

# Used for both the n-gram and the embedding-based similarities.
%/p_clust.tsv: %/p_sim.csv
	csvcut -c poem_id_1,poem_id_2,sim $< \
	| tail -n +2 | csvformat -T | sort > $@.edges
	cut -f 1 $@.edges | uniq > $@.nodes
	echo | cat $@.nodes - $@.edges | shortsim-cluster -s 0.1 > $@
	rm $@.nodes $@.edges

.PHONY: poem_clust

p_sim_part_%: $(p_sim_parts_dir)/part_%.csv ;

poem_clust: $(DATA_DIR)/p_sim.csv $(DATA_DIR)/p_clust.tsv

###################################################################
# EMBEDDING-BASED SIMILARITY AND CLUSTERING
###################################################################

# The same tables as above, computed from precomputed verse embeddings
# (https://a3s.fi/filter-data/index.html) instead of character n-grams.
# They are written to $(DATA_DIR)/emb/$(EMB_MODEL), with the same file
# names and formats. Verses without an embedding get a zero vector.
#
# There are no n-gram weightings here, so v_clust.tsv only contains three
# clusterings: emb, emb-tight and emb-loose (the counterparts of default,
# tight and loose). Runoregi uses the clustering IDs as positions in the
# list of clusterings, so they must continue the numbering without gaps:
# by default they follow the six n-gram clusterings (6, 7, 8), so that both
# can be loaded into the same tables. Use EMB_CLUST_ID=0 for a database with
# only the embedding-based clusterings.

EMB_MODEL ?= filter_p4_vb_v45_w45_m10_iso
EMB_URL ?= https://a3s.fi/filter-data
# Minimum cosine similarity of verse embeddings (the threshold for which
# the FILTER models' similarity tables were tuned).
EMB_THR ?= 0.7
# ID of the first embedding-based verse clustering (see above).
EMB_CLUST_ID ?= 6

emb_dir = $(DATA_DIR)/emb/$(EMB_MODEL)
emb_work = $(work_dir)/emb/$(EMB_MODEL)
emb_file = $(work_dir)/emb/verse_embeddings_$(EMB_MODEL).parquet
emb_poems_file = $(work_dir)/emb/poems.parquet

$(work_dir)/emb/%.parquet:
	mkdir -p $(@D)
	curl -fsSL -o $@ $(EMB_URL)/$*.parquet

# one row per distinct verse text (for verse similarity)
$(emb_work)/verse_vectors.npy: \
  $(work_dir)/verse_sim/verses_cl.list.txt \
  $(DATA_DIR)/verses_cl.csv \
  $(emb_file) $(emb_poems_file)
	mkdir -p $(@D)
	$(python) code/load_embeddings.py -e $(emb_file) -p $(emb_poems_file) \
	  -i $(DATA_DIR)/verses_cl.csv -t $< -o $@

# one row per verse occurrence (for poem similarity)
$(emb_work)/poem_vectors.npy: \
  $(work_dir)/verses_cl_by_length.csv \
  $(emb_file) $(emb_poems_file)
	mkdir -p $(@D)
	$(python) code/load_embeddings.py -e $(emb_file) -p $(emb_poems_file) \
	  -i $< -o $@

$(emb_dir)/v_sim.tsv: \
  $(work_dir)/verse_sim/verses_cl.list.txt \
  $(emb_work)/verse_vectors.npy
	mkdir -p $(@D)
	$(python) code/emb_verse_sim.py -e $(emb_work)/verse_vectors.npy \
	  -t $(EMB_THR) $(GPU_FLAG) -p < $< > $@

emb_clust_thr_default = 0.8
emb_clust_thr_tight = 0.85
emb_clust_thr_loose = 0.75

$(emb_work)/v_clust.%.tsv: \
  $(work_dir)/verse_sim/verses_cl.list.txt \
  $(emb_dir)/v_sim.tsv
	echo | cat $< - $(emb_dir)/v_sim.tsv \
	| shortsim-cluster -s $(emb_clust_thr_$*) > $@

$(emb_dir)/v_clust.tsv: \
  $(emb_work)/v_clust.default.tsv \
  $(emb_work)/v_clust.tight.tsv \
  $(emb_work)/v_clust.loose.tsv
	sed 's/^/$(EMB_CLUST_ID)\t/' $(emb_work)/v_clust.default.tsv > $@
	sed 's/^/$(shell echo $$(($(EMB_CLUST_ID)+1)))\t/' $(emb_work)/v_clust.tight.tsv >> $@
	sed 's/^/$(shell echo $$(($(EMB_CLUST_ID)+2)))\t/' $(emb_work)/v_clust.loose.tsv >> $@

$(emb_dir)/v_clusterings.csv:
	mkdir -p $(@D)
	echo 'clustering_id,name,description' > $@
	echo '$(EMB_CLUST_ID),emb,"$(EMB_MODEL)"' >> $@
	echo '$(shell echo $$(($(EMB_CLUST_ID)+1))),emb-tight,"$(EMB_MODEL), threshold = 0.85"' >> $@
	echo '$(shell echo $$(($(EMB_CLUST_ID)+2))),emb-loose,"$(EMB_MODEL), threshold = 0.75"' >> $@

emb_p_sim_parts_dir = $(emb_work)/p_sim/$(POEM_SIM_JOBS)
emb_p_sim_parts = $(foreach i,$(shell seq 0 $$(($(POEM_SIM_JOBS)-1))),\
                    $(emb_p_sim_parts_dir)/part_$(i).csv)

$(emb_p_sim_parts_dir)/part_%.csv: \
  $(work_dir)/verses_cl_by_length.csv \
  $(emb_work)/poem_vectors.npy
	mkdir -p $(emb_p_sim_parts_dir)
	$(python) code/poem_sim.py -e $(emb_work)/poem_vectors.npy \
	  -t $(EMB_THR) -p -r $(GPU_FLAG) -i $< -o $@ \
	  -j $* -J $(POEM_SIM_JOBS) \
	  --sim-raw-thr 1 --sim-onesided-thr 0.1 --sim-sym-thr 0 \
	  -L DEBUG --logfile $(emb_p_sim_parts_dir)/part_$*.log

$(emb_dir)/p_sim.csv: $(emb_p_sim_parts)
	head -n 1 $< > $@
	for f in $^; do tail -n +2 $$f; done >> $@

.PHONY: emb_vectors emb_verse_sim emb_verse_clust emb_poem_clust

emb_vectors: $(emb_work)/verse_vectors.npy $(emb_work)/poem_vectors.npy

emb_verse_sim: $(emb_dir)/v_sim.tsv

emb_verse_clust: $(emb_dir)/v_clust.tsv $(emb_dir)/v_clusterings.csv

emb_p_sim_part_%: $(emb_p_sim_parts_dir)/part_%.csv ;

emb_poem_clust: $(emb_dir)/p_sim.csv $(emb_dir)/p_clust.tsv


###################################################################
# RUNOREGI DATABASE
###################################################################

# The tables of the runoregi database as Parquet files, in
# $(RUNOREGI_DIR). First the tables are prepared as CSV files with unique
# numeric keys (adapted from https://github.com/jakobytes/filter-db), then
# converted to Parquet by export_runoregi.py, which mimics the MariaDB
# database that filter-db creates (column types, primary keys, computed
# frequency and statistics tables).
#
# The verse similarities and the poem similarities and clustering are the
# n-gram ones. With RUNOREGI_EMB set to an embedding model (see EMB_MODEL),
# its verse clusterings are added to v_clust and v_clusterings.

RUNOREGI_DIR ?= $(DATA_DIR)/runoregi
RUNOREGI_EMB ?=

tbl_dir = $(work_dir)/runoregi
trk = $(python) code/translate_keys.py

runoregi_v_clust = $(DATA_DIR)/v_clust.tsv \
  $(if $(RUNOREGI_EMB),$(DATA_DIR)/emb/$(RUNOREGI_EMB)/v_clust.tsv)
runoregi_v_clusterings = $(DATA_DIR)/v_clusterings.csv \
  $(if $(RUNOREGI_EMB),$(DATA_DIR)/emb/$(RUNOREGI_EMB)/v_clusterings.csv)

runoregi_tables = \
  collectors maps map_pol places polygons pol_pl poems p_col p_dupl \
  p_pl p_typ p_year raw_meta refs runoregi_pages types verses verse_poem \
  verses_cl word_occ words v_clusterings v_clust v_sim p_sim p_clust \
  v_clust_freq p_clust_freq word_freq place_stats dbmeta

.PHONY: runoregi

runoregi: $(patsubst %,$(RUNOREGI_DIR)/%.parquet,$(runoregi_tables))

$(patsubst %,$(RUNOREGI_DIR)/%.parquet,$(runoregi_tables)) &: \
  $(tbl_dir)/collectors.tbl.csv \
  $(tbl_dir)/maps.tbl.csv \
  $(tbl_dir)/map_pol.tbl.csv \
  $(tbl_dir)/places.tbl.csv \
  $(tbl_dir)/polygons.tbl.csv \
  $(tbl_dir)/pol_pl.tbl.csv \
  $(tbl_dir)/poems.tbl.csv \
  $(tbl_dir)/p_col.tbl.csv \
  $(tbl_dir)/p_dupl.tbl.csv \
  $(tbl_dir)/p_pl.tbl.csv \
  $(tbl_dir)/p_typ.tbl.csv \
  $(tbl_dir)/p_year.tbl.csv \
  $(tbl_dir)/raw_meta.tbl.csv \
  $(tbl_dir)/refs.tbl.csv \
  $(tbl_dir)/runoregi_pages.tbl.tsv \
  $(tbl_dir)/types.tbl.csv \
  $(tbl_dir)/verses.tbl.csv \
  $(tbl_dir)/verse_poem.tbl.csv \
  $(tbl_dir)/verses_cl.tbl.csv \
  $(tbl_dir)/word_occ.tbl.csv \
  $(tbl_dir)/words.tbl.csv \
  $(tbl_dir)/v_clusterings.tbl.csv \
  $(tbl_dir)/v_clust.tbl.csv \
  $(tbl_dir)/v_sim.tbl.csv \
  $(tbl_dir)/p_sim.tbl.csv \
  $(tbl_dir)/p_clust.tbl.csv
	$(python) code/export_runoregi.py -i $(tbl_dir) -o $(RUNOREGI_DIR)

# The key dictionaries (*.idmap.csv, verses.tbl.csv, words.tbl.csv) are
# extended by the rules using them, so the order of the rules matters:
# poems and verses first.

$(tbl_dir)/collectors.tbl.csv: $(DATA_DIR)/collectors.csv
	mkdir -p $(tbl_dir)
	$(trk) -i $< \
	       -o /dev/null \
	       -d collector_id,collector_name:col_id:$@

$(tbl_dir)/maps.tbl.csv:
	mkdir -p $(tbl_dir)
	echo 'map_id,name' > $@
	echo '0,"parishes (all)"' >> $@
	echo '1,"counties (all)"' >> $@
	echo '2,"parishes (Northern)"' >> $@
	echo '3,"counties (Northern)"' >> $@
	echo '4,"parishes (Southern)"' >> $@
	echo '5,"counties (Southern)"' >> $@

$(tbl_dir)/map_pol.tbl.csv: \
  $(DATA_DIR)/areas.geojson \
  $(DATA_DIR)/counties.geojson
	mkdir -p $(tbl_dir)
	echo 'map_id,pol_id' > $@
	jq -r '.features[] | [.properties.id ] | @csv' \
	  $(DATA_DIR)/areas.geojson \
	| sed 's/^/0,/' >> $@
	jq -r '.features[] | [.properties.id ] | @csv' \
	  $(DATA_DIR)/counties.geojson \
	| sed 's/^/1,/' >> $@
	jq -r '.features[] | select(.properties.parish_name == "Setumaa") '\
	'      | [.properties.id] | @tsv' $(DATA_DIR)/areas.geojson \
	| sed 's/^/1,/' >> $@
	jq -r '.features[] | select(.properties.parish_language != null) '\
	'      | select(.properties.parish_language | test("kaA|su|ru|kaV|ka|in|ve|suI|ly"; ""))'\
	'      | [ .properties.id ] | @csv' $(DATA_DIR)/areas.geojson \
	| sed 's/^/2,/' >> $@
	jq -r '.features[] | select(.properties.county_language != null) '\
	'      | select(.properties.county_language | test("kaA|su|ru|kaV|ka|in|ve|suI|ly"; ""))'\
	'      | [ .properties.id ] | @csv' $(DATA_DIR)/counties.geojson \
	| sed 's/^/3,/' >> $@
	jq -r '.features[] | select(.properties.parish_language != null) '\
	'      | select(.properties.parish_language | test("viP|viE"; ""))'\
	'      | [ .properties.id ] | @csv' $(DATA_DIR)/areas.geojson \
	| sed 's/^/4,/' >> $@
	jq -r '.features[] | select(.properties.county_language != null) '\
	'      | select(.properties.county_language | test("viP|viE"; ""))'\
	'      | [ .properties.id ] | @csv' $(DATA_DIR)/counties.geojson \
	| sed 's/^/5,/' >> $@
	jq -r '.features[] | select(.properties.parish_name == "Setumaa") '\
	'      | [.properties.id] | @tsv' $(DATA_DIR)/areas.geojson \
	| sed 's/^/5,/' >> $@

$(tbl_dir)/places.tbl.csv: $(DATA_DIR)/places.csv
	mkdir -p $(tbl_dir)
	$(trk) -i $< -o $(tbl_dir)/places.tmp1.csv \
	       -d place_id:pl_id:$(tbl_dir)/places.idmap.csv
	$(trk) -i $(tbl_dir)/places.tmp1.csv \
	       -o $(tbl_dir)/places.tmp2.csv \
	       -d place_parent_id:par_id:$(tbl_dir)/places.idmap.csv:par_id,place_parent_id
	sed -i '1s/par_id,place_parent_id/pl_id,place_id/' $(tbl_dir)/places.idmap.csv
	ROOT_PLACE_ID=$$(tail -n 1 $(tbl_dir)/places.idmap.csv | cut -d, -f 1) \
	&& sed -i "s/,$$ROOT_PLACE_ID\$$/,/" $(tbl_dir)/places.tmp2.csv
	csvjoin -c pl_id $(tbl_dir)/places.idmap.csv \
	                 $(tbl_dir)/places.tmp2.csv > $@
	rm -f $(tbl_dir)/places.tmp*

$(tbl_dir)/polygons.tbl.csv: \
  $(DATA_DIR)/areas.geojson \
  $(DATA_DIR)/counties.geojson
	mkdir -p $(tbl_dir)
	jq -r '.features[] | [.properties.id, .properties.parish_scripts,'\
	'                     .properties.parish_language, .properties.parish_name,'\
	'                     .geometry | tostring] | @tsv' \
	  $(DATA_DIR)/areas.geojson > $@
	jq -r '.features[] | [.properties.id, null,'\
	'                     .properties.county_language, .properties.county_name,'\
	'                     .geometry | tostring] | @tsv' \
	  $(DATA_DIR)/counties.geojson >> $@

$(tbl_dir)/pol_pl.tbl.csv: \
  $(DATA_DIR)/polygon_to_place.csv \
  $(tbl_dir)/places.tbl.csv
	$(trk) -i $(DATA_DIR)/polygon_to_place.csv -O \
	  -d place_id:pl_id:$(tbl_dir)/places.idmap.csv > $@

$(tbl_dir)/types.tbl.csv: $(DATA_DIR)/types.csv
	mkdir -p $(tbl_dir)
	$(trk) -i $< -o $(tbl_dir)/types.tmp1.csv \
	       -d type_id:t_id:$(tbl_dir)/types.idmap.csv
	$(trk) -i $(tbl_dir)/types.tmp1.csv \
	       -o $(tbl_dir)/types.tmp2.csv \
	       -d type_parent_id:par_id:$(tbl_dir)/types.idmap.csv:par_id,type_parent_id
	sed -i '1s/par_id,type_parent_id/t_id,type_id/' $(tbl_dir)/types.idmap.csv
	ROOT_TYPE_ID=$$(tail -n 1 $(tbl_dir)/types.idmap.csv | cut -d, -f 1) \
	&& sed -i "s/,$$ROOT_TYPE_ID\$$/,/" $(tbl_dir)/types.tmp2.csv
	csvjoin -c t_id $(tbl_dir)/types.idmap.csv \
	                $(tbl_dir)/types.tmp2.csv > $@
	rm -f $(tbl_dir)/types.tmp*

$(tbl_dir)/poems.tbl.csv: $(DATA_DIR)/poems.csv
	mkdir -p $(tbl_dir)
	$(trk) -a -i $< -o $@ -d poem_id:p_id:$(tbl_dir)/poems.idmap.csv

$(tbl_dir)/verses.tbl.csv: $(tbl_dir)/verse_poem.tbl.csv

$(tbl_dir)/verse_poem.tbl.csv: \
  $(DATA_DIR)/verses.csv \
  $(tbl_dir)/poems.tbl.csv
	$(trk) -i $(DATA_DIR)/verses.csv -o $@ \
	       -d verse_type,text:v_id:$(tbl_dir)/verses.tbl.csv \
	          poem_id:p_id:$(tbl_dir)/poems.idmap.csv

$(tbl_dir)/verses_cl.tbl.csv: \
  $(DATA_DIR)/verses_cl.csv \
  $(tbl_dir)/verse_poem.tbl.csv
	$(trk) -i $< -d poem_id:p_id:$(tbl_dir)/poems.idmap.csv \
	| $(python) code/map_columns.py -u -f p_id,pos -t v_id \
	    $(tbl_dir)/verse_poem.tbl.csv > $@

$(tbl_dir)/word_occ.tbl.csv: \
  $(DATA_DIR)/word_occ.csv \
  $(tbl_dir)/verse_poem.tbl.csv
	$(trk) -i $< -d poem_id:p_id:$(tbl_dir)/poems.idmap.csv \
	                text:w_id:$(tbl_dir)/words.tbl.csv \
	| $(python) code/map_columns.py -u -f p_id,pos -t v_id \
	    $(tbl_dir)/verse_poem.tbl.csv > $@

$(tbl_dir)/words.tbl.csv: $(tbl_dir)/word_occ.tbl.csv

$(tbl_dir)/raw_meta.tbl.csv: \
  $(DATA_DIR)/raw_meta.csv \
  $(tbl_dir)/poems.tbl.csv
	$(trk) -i $< -o $@ -d poem_id:p_id:$(tbl_dir)/poems.idmap.csv

$(tbl_dir)/p_col.tbl.csv: \
  $(DATA_DIR)/poem_collector.csv \
  $(tbl_dir)/poems.tbl.csv \
  $(tbl_dir)/collectors.tbl.csv
	csvcut -c col_id,collector_id $(tbl_dir)/collectors.tbl.csv \
	  > $(tbl_dir)/collectors.idmap.csv
	$(trk) -O -i $< -o $@ \
	       -d poem_id:p_id:$(tbl_dir)/poems.idmap.csv \
	          collector_id:col_id:$(tbl_dir)/collectors.idmap.csv

$(tbl_dir)/runoregi_pages.tbl.tsv: $(DATA_DIR)/runoregi_pages.tsv
	mkdir -p $(tbl_dir)
	cp $< $@

$(tbl_dir)/p_dupl.tbl.csv: \
  $(DATA_DIR)/poem_duplicates.csv \
  $(tbl_dir)/poems.tbl.csv
	$(trk) -O -i $< -o $@ \
	       -d poem_id:p_id:$(tbl_dir)/poems.idmap.csv \
	          master_poem_id:master_p_id:$(tbl_dir)/poems.idmap.csv:master_p_id,master_poem_id

$(tbl_dir)/p_pl.tbl.csv: \
  $(DATA_DIR)/poem_place.csv \
  $(tbl_dir)/poems.tbl.csv \
  $(tbl_dir)/places.tbl.csv
	$(trk) -O -i $< -o $@ \
	       -d poem_id:p_id:$(tbl_dir)/poems.idmap.csv \
	          place_id:pl_id:$(tbl_dir)/places.idmap.csv

$(tbl_dir)/p_year.tbl.csv: \
  $(DATA_DIR)/poem_year.csv \
  $(tbl_dir)/poems.tbl.csv
	$(trk) -O -i $< -o $@ -d poem_id:p_id:$(tbl_dir)/poems.idmap.csv

$(tbl_dir)/p_typ.tbl.csv: \
  $(DATA_DIR)/poem_types.csv \
  $(tbl_dir)/poems.tbl.csv \
  $(tbl_dir)/types.tbl.csv
	$(trk) -O -i $< -o $@ \
	       -d poem_id:p_id:$(tbl_dir)/poems.idmap.csv \
	          type_id:t_id:$(tbl_dir)/types.idmap.csv

$(tbl_dir)/refs.tbl.csv: \
  $(DATA_DIR)/refs.csv \
  $(tbl_dir)/poems.tbl.csv
	$(trk) -i $< -o $@ -d poem_id:p_id:$(tbl_dir)/poems.idmap.csv

$(tbl_dir)/p_sim.tbl.csv: \
  $(DATA_DIR)/p_sim.csv \
  $(tbl_dir)/poems.tbl.csv
	$(trk) -O -i $< -o $@ \
	  -d poem_id_1:p1_id:$(tbl_dir)/poems.idmap.csv:p1_id,poem_id_1 \
	     poem_id_2:p2_id:$(tbl_dir)/poems.idmap.csv:p2_id,poem_id_2

$(tbl_dir)/p_clust.tbl.csv: \
  $(DATA_DIR)/p_clust.tsv \
  $(tbl_dir)/poems.tbl.csv
	csvformat -t $< | sed '1ipoem_id,clust_id' \
	| $(trk) -i - -o $@ -d poem_id:p_id:$(tbl_dir)/poems.idmap.csv

$(tbl_dir)/v_clusterings.tbl.csv: $(runoregi_v_clusterings)
	mkdir -p $(tbl_dir)
	head -n 1 $< > $@
	for f in $^; do tail -n +2 $$f; done >> $@

$(tbl_dir)/v_sim.tbl.csv: \
  $(DATA_DIR)/v_sim.tsv \
  $(tbl_dir)/verses_cl.tbl.csv
	csvformat -t $< | sed '1itext_1,text_2,sim' \
	| $(python) code/map_columns.py -m -f text_1 -t v1_id -H v1_id,text_1 \
	                                 $(tbl_dir)/verses_cl.tbl.csv \
	| $(python) code/map_columns.py -m -f text_2 -t v2_id -H v2_id,text_2 \
	                                 $(tbl_dir)/verses_cl.tbl.csv > $@

$(tbl_dir)/v_clust.tbl.csv: \
  $(runoregi_v_clust) \
  $(tbl_dir)/verses_cl.tbl.csv
	cat $(runoregi_v_clust) | csvformat -t | sed '1iclustering_id,text,clust_id' \
	| $(python) code/map_columns.py -m -f text -t v_id \
	                                 $(tbl_dir)/verses_cl.tbl.csv > $@
