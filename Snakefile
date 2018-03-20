# vim: syntax=python expandtab
#
# mwc - Metagenomic Workflow Collaboration
# Copyright (c) 2018 Authors
#
# Running snakemake -n in a clone of this repository should successfully
# execute a test dry-run of the workflow.

configfile: "config.yaml"
outdir = config["outdir"]
all_outputs = []

SAMPLES = glob_wildcards(config["inputdir"]+"/"+config["input_fn_pattern"]).sample


if config["qc_reads"]:
    include: "rules/preproc/read_quality.smk"
    fastqc_input = expand("{outdir}/fastqc/{sample}_R{readpair}.{ext}", outdir=outdir, sample=SAMPLES, readpair=[1,2], ext=["zip", "html"])
    trimmed_qa = expand("{outdir}/trimmed_qa/{sample}_R{readpair}.trimmed_qa.fq.gz", outdir=outdir, sample=SAMPLES, readpair=[1,2])
    all_outputs.extend(fastqc_input)
    all_outputs.extend(trimmed_qa)


if config["remove_human"]:
    include: "rules/preproc/remove_human.smk"
    filtered_human = expand("{outdir}/filtered_human/{sample}_R{readpair}.filtered_human.fq.gz", outdir=outdir, sample=SAMPLES, readpair=[1,2])
    all_outputs.extend(filtered_human)
    hg19_db_dir = config["dbdir"]+"/hg19"
    hg19_db_file = "hg19_main_mask_ribo_animal_allplant_allfungus.fa"
    if not os.path.exists(os.path.join(hg19_db_dir, hg19_db_file)):
        all_outputs.extend(expand("{dbdir}/{dbfile}", dbdir=hg19_db_dir, dbfile=hg19_db_file))


if config["taxonomic_profile"]:
    include: "rules/taxonomic_profiling/kaiju.smk"
    kaiju = expand("{outdir}/kaiju/{sample}.kaiju", outdir=outdir, sample=SAMPLES)
    kaiju_reports = expand("{outdir}/kaiju/{sample}.kaiju.summary.species", outdir=outdir, sample=SAMPLES)
    all_outputs.extend(kaiju)
    all_outputs.extend(kaiju_reports)
    kaiju_db_dir = config["dbdir"]+"/kaiju"
    kaiju_db_files = ["kaiju_db.fmi", "names.dmp", "nodes.dmp"]
    if not all([os.path.exists(os.path.join(kaiju_db_dir, dbfile)) for dbfile in kaiju_db_files]):
        all_outputs.extend(expand("{dbdir}/{dbfile}", dbdir=kaiju_db_dir, dbfile=kaiju_db_files))


rule all:
    input:
        all_outputs
