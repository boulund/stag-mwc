# vim: syntax=python expandtab
# Assembly and binning of metagenomic assemblies using MetaWRAP:
#   - MEGAHIT
#   - MaxBin2, CONCOCT, MetaBAT
# TODO: Remove superfluous str conversions when Snakemake is pathlib compatible.
from pathlib import Path

from snakemake.exceptions import WorkflowError

localrules:

if config["assembly"]:
    assemblies = expand(str(OUTDIR/"metawrap/assembly/{sample}/final_assembly.fasta"), sample=SAMPLES)
    all_outputs.extend(assemblies)

    citations.add((
        "Uritskiy, Gherman V., DiRuggiero, Jocelyne, Taylor, James (2018).",
        "MetaWRAP—a flexible pipeline for genome-resolved metagenomic data analysis."
        "Microbiome 158:8, doi: 10.1186/s40168-018-0541-1"
    ))
    citations.add((
       "Li, D., Liu, C-M., Luo, R., Sadakane, K., and Lam, T-W., (2015).",
        "MEGAHIT: An ultra-fast single-node solution for large and complex metagenomics assembly via succinct de Bruijn graph.",
        "Bioinformatics, doi: 10.1093/bioinformatics/btv033 [PMID: 25609793]."
    ))

if config["binning"]:
    primary_bins = expand(str(OUTDIR/"metawrap/binning/{sample}/concoct_bins"), sample=SAMPLES)
    consolidated_bins = expand(str(OUTDIR/"metawrap/consolidated_bins/{sample}/metawrap"), sample=SAMPLES)
    blobology = expand(str(OUTDIR/"metawrap/blobology/{sample}"), sample=SAMPLES)
    all_outputs.extend(primary_bins)
    all_outputs.extend(consolidated_bins)
    all_outputs.extend(blobology)

    citations.add((
        "Uritskiy, Gherman V., DiRuggiero, Jocelyne, Taylor, James (2018).",
        "MetaWRAP—a flexible pipeline for genome-resolved metagenomic data analysis."
        "Microbiome 158:8, doi: 10.1186/s40168-018-0541-1"
    ))
    citations.add((
        "Alneberg, J., Bjarnason, B.S., de Bruijn, I., Schirmer, M., Quick, J., Ijaz, U.Z., Lahti, L., Loman, N.J, Andersson, A.F, Quince, C. (2014).",
        "Binning metagenomic contigs by coverage and composition.",
        "Nature Methods, doi: 10.1038/nmeth.3103",
    ))
    citations.add((
        "Kang DD, Li F, Kirton E, Thomas A, Egan R, An H, Wang Z. (2019).",
        "MetaBAT 2: an adaptive binning algorithm for robust and efficient genome reconstruction from metagenome assemblies.",
        "PeerJ 7:e7359 https://doi.org/10.7717/peerj.7359",
    ))
    citations.add((
        "Yu-Wei Wu, Blake A. Simmons, Steven W. Singer (2016).",
        "MaxBin 2.0: an automated binning algorithm to recover genomes from multiple metagenomic datasets.",
        "Bioinformatics, Volume 32, Issue 4, 15 February 2016, Pages 605–607, https://doi.org/10.1093/bioinformatics/btv638",
    ))



mw_config = config["metawrap"]
rule assembly:
    """Metagenomic assembly using MEGAHIT via MetaWRAP."""
    input:
        read1=OUTDIR/"filtered_human/{sample}_R1.filtered_human.fq.gz",
        read2=OUTDIR/"filtered_human/{sample}_R2.filtered_human.fq.gz",
    output:
        contigs=OUTDIR/"metawrap/assembly/{sample}/final_assembly.fasta",
    log:
        stdout=str(LOGDIR/"metawrap/{sample}.assembly.stdout.log"),
        stderr=str(LOGDIR/"metawrap/{sample}.assembly.stderr.log"),
    shadow:
        "shallow"
    conda:
        "../../envs/assembly.yaml"
    threads:
        20
    params:
        outdir=lambda w: f"{OUTDIR}/metawrap/assembly/{w.sample}",
    shell:
        """
        metawrap assembly \
            -1 {input.read1} \
            -2 {input.read2} \
            -o {params.outdir} \
            -t {threads} \
            -m 24 \
            --megahit \
            2> {log.stderr} \
            > {log.stdout}
        """


rule binning:
    """Metagenomic binning using CONCOCT, MaxBin2, MetaBAT via MetaWRAP."""
    input:
        contigs=OUTDIR/"metawrap/assembly/{sample}/final_assembly.fasta",
        read1=OUTDIR/"filtered_human/{sample}_R1.filtered_human.fq.gz",
        read2=OUTDIR/"filtered_human/{sample}_R2.filtered_human.fq.gz",
    output:
        concoct_bins=OUTDIR/"metawrap/binning/{sample}/concoct_bins",
        #maxbin2_bins=OUTDIR/"metawrap/binning/{sample}/maxbin2_bins",
        metabat2_bins=OUTDIR/"metawrap/binning/{sample}/metabat2_bins",
    log:
        stdout=str(LOGDIR/"metawrap/{sample}.binning.stdout.log"),
        stderr=str(LOGDIR/"metawrap/{sample}.binning.stderr.log"),
    shadow:
        "shallow"
    conda:
        "../../envs/assembly.yaml"
    threads:
        20
    params:
        outdir=lambda w: f"{OUTDIR}/metawrap/binning/{w.sample}",
        universal=mw_config["universal"],
    shell:
        """
        gunzip -c {input.read1} > reads_1.fastq
        gunzip -c {input.read2} > reads_2.fastq
        metawrap binning \
            -a {input.contigs} \
            -o {params.outdir} \
            -t {threads} \
            -m 32 \
            --concoct \
            --metabat2 \
            --run-checkm \
            {params.universal} \
           reads_1.fastq reads_2.fastq \
            2> {log.stderr} \
            > {log.stdout}
        """

rule consolidate_bins:
    """Consolidate bins using MetaWRAP."""
    input:
        concoct_bins=OUTDIR/"metawrap/binning/{sample}/concoct_bins",
        #maxbin2_bins=OUTDIR/"metawrap/binning/{sample}/maxbin2_bins",
        metabat2_bins=OUTDIR/"metawrap/binning/{sample}/metabat2_bins",
    output:
        metawrap_bins=OUTDIR/"metawrap/consolidated_bins/{sample}/metawrap",
        metawrap_stats=OUTDIR/"metawrap/consolidated_bins/{sample}/metawrap.stats",
    log:
        stdout=str(LOGDIR/"metawrap/{sample}.consolidate_bins.stdout.log"),
        stderr=str(LOGDIR/"metawrap/{sample}.consolidate_bins.stderr.log"),
    shadow:
        "shallow"
    conda:
        "../../envs/assembly.yaml"
    threads:
        20
    params:
        outdir=lambda w: f"{OUTDIR}/metawrap/consolidated_bins/{w.sample}",
        minimum_completion=mw_config["minimum_completion"],
        maximum_contamination=mw_config["maximum_contamination"],
    shell:
        """
        metawrap bin_refinement \
            -o {params.outdir} \
            -t {threads} \
            -c {params.minimum_completion} \
            -x {params.maximum_contamination} \
            -A {input.concoct_bins} \
            -B {input.metabat2_bins} \
            2> {log.stderr} \
            > {log.stdout}
        """


rule blobology:
    """Visualize bins using MetaWRAP blobology module"""
    input:
        contigs=OUTDIR/"metawrap/assembly/{sample}/final_assembly.fasta",
        metawrap_bins=OUTDIR/"metawrap/consolidated_bins/{sample}/metawrap",
        read1=OUTDIR/"filtered_human/{sample}_R1.filtered_human.fq.gz",
        read2=OUTDIR/"filtered_human/{sample}_R2.filtered_human.fq.gz",
    output:
        plots=OUTDIR/"metawrap/blobology/{sample}",
    log:
        stdout=str(LOGDIR/"metawrap/{sample}.blobology.stdout.log"),
        stderr=str(LOGDIR/"metawrap/{sample}.blobology.stderr.log"),
    shadow:
        "shallow"
    conda:
        "../../envs/assembly.yaml"
    threads:
        20
    params:
        outdir=lambda w: f"{OUTDIR}/metawrap/blobology/{w.sample}",
    shell:
        """
        metawrap blobology \
            -a {input.contigs} \
            -t {threads} \
            -o {params.outdir} \
            --bins {input.metawrap_bins} \
            {input.read1} {input.read2} \
            2> {log.stderr} \
            > {log.stdout}
        """
