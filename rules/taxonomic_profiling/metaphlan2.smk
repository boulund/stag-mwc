# vim: syntax=python expandtab
# Taxonomic classification of metagenomic reads using MetaPhlAn2
# TODO: Remove superfluous str conversions when Snakemake is pathlib compatible.
from pathlib import Path

from snakemake.exceptions import WorkflowError

localrules:
    plot_metaphlan2_heatmap,
    create_metaphlan2_krona_plots,
    metaphlan2_krona,

mpa_config = config["metaphlan2"]
if config["taxonomic_profile"]["metaphlan2"]:
    if not mpa_config["bt2_db_dir"] or not Path(mpa_config["bt2_db_dir"]).exists():
        err_message = "No MetaPhlAn2 database dir found at: '{}'!\n".format(mpa_config["bt2_db_dir"])
        err_message += "Specify relevant paths in the metaphlan2 section of config.yaml.\n"
        err_message += "If you do not want to run MetaPhlAn2 for taxonomic profiling, set metaphlan2: False in config.yaml"
        raise WorkflowError(err_message)

    # Add MetaPhlAn2 output files to 'all_outputs' from the main Snakefile scope.
    # SAMPLES is also from the main Snakefile scope.
    mpa_outputs = expand(f"{OUTDIR}/metaphlan2/{{sample}}.{{output_type}}",
            sample=SAMPLES,
            output_type=("bowtie2.bz2", "metaphlan2.txt", "metaphlan2.krona"))
    mpa_combined = expand(f"{OUTDIR}/metaphlan2/all_samples.metaphlan2.{{ext}}",
            ext=("txt", "krona.html"))
    mpa_plot = f"{OUTDIR}/metaphlan2/all_samples.{mpa_config['heatmap']['level']}_top{mpa_config['heatmap']['topN']}.pdf"
    all_outputs.extend(mpa_outputs)
    all_outputs.extend(mpa_combined)
    all_outputs.append(mpa_plot)

    citations.add((
        "Truong, D. T., et al. (2015).",
        "MetaPhlAn2 for enhanced metagenomic taxonomic profiling.",
        "Nature methods, 12(10), 902.",
        "https://doi.org/10.1038/nmeth.3589",
    ))
    citations.add((
        "Ondov BD, Bergman NH, and Phillippy AM.",
        "Interactive metagenomic visualization in a Web browser.",
        "BMC Bioinformatics. 2011 Sep 30; 12(1):385.",
        "https://doi.org/10.1186/1471-2105-12-385",
    ))


rule metaphlan2:
    """Taxonomic profiling using MetaPhlAn2."""
    input:
        read1=OUTDIR/"host_removal/{sample}_1.fq.gz",
        read2=OUTDIR/"host_removal/{sample}_2.fq.gz",
    output:
        bt2_out=OUTDIR/"metaphlan2/{sample}.bowtie2.bz2",
        mpa_out=OUTDIR/"metaphlan2/{sample}.metaphlan2.txt",
    log:
        stdout=str(LOGDIR/"metaphlan2/{sample}.metaphlan2.stdout.log"),
        stderr=str(LOGDIR/"metaphlan2/{sample}.metaphlan2.stderr.log"),
    shadow:
        "shallow"
    conda:
        "../../envs/metaphlan2.yaml"
    threads:
        5
    params:
        bt2_db_dir=mpa_config["bt2_db_dir"],
        bt2_index=mpa_config["bt2_index"],
        extra=mpa_config["extra"],
    shell:
        """
        metaphlan2.py \
            --input_type fastq \
            --nproc {threads} \
            --sample_id {wildcards.sample} \
            --bowtie2out {output.bt2_out} \
            --bowtie2db {params.bt2_db_dir} \
            --index {params.bt2_index} \
            {input.read1},{input.read2} \
            {output.mpa_out} \
            {params.extra} \
            > {log.stdout} \
            2> {log.stderr}
        """


rule metaphlan2_krona:
    """Convert MPA2 output to Krona input"""
    input:
        mpa_out=OUTDIR/"metaphlan2/{sample}.metaphlan2.txt",
    output:
        krona=OUTDIR/"metaphlan2/{sample}.metaphlan2.krona",
    log:
        str(LOGDIR/"metaphlan2/{sample}.metaphlan2_krona.log"),
    shadow:
        "shallow"
    shell:
        """
        # This command is broken in MetaPhlAn2 v2.96.1 when running with old DB
        #metaphlan2krona.py \
        #    --profile {input.mpa_out} \
        #    --krona {output.krona} \
        #    2>&1 > {log}
       
        set +o pipefail  # Small samples can produce empty output files failing the pipeline
        sed '/#/d' {input.mpa_out} \
            | grep -E "s__|unclassified" \
            | cut -f1,3 \
            | awk '{{print $2,"\t",$1}}' \
            | sed 's/|\w__/\t/g' \
            | sed 's/k__//' \
            > {output.krona} \
            2> {log}
        """

rule combine_metaphlan2_tables:
    """Combine metaphlan2 outputs into a large table."""
    input:
        expand(f"{OUTDIR}/metaphlan2/{{sample}}.metaphlan2.txt", sample=SAMPLES)
    output:
        txt=report(f"{OUTDIR}/metaphlan2/all_samples.metaphlan2.txt",
                   category="Taxonomic profiling",
                   caption="../../report/metaphlan2_table.rst"),
    log:
        f"{LOGDIR}/metaphlan2/combine_metaphlan2_tables.log",
    shadow:
        "shallow"
    conda:
        "../../envs/metaphlan2.yaml"
    threads:
        1
    shell:
        """
        merge_metaphlan_tables.py {input} > {output.txt}
        sed --in-place 's/\.metaphlan2//g' {output.txt} 
        """

rule plot_metaphlan2_heatmap:
    """Plot MetaPhlAn2 heatmap."""
    input:
        f"{OUTDIR}/metaphlan2/all_samples.metaphlan2.txt",
    output:
        pdf=report(f"{OUTDIR}/metaphlan2/all_samples.{{level}}_top{{topN}}.pdf",
                   category="Taxonomic profiling",
                   caption="../../report/metaphlan2.rst"),
    log:
        f"{LOGDIR}/metaphlan2/plot_metaphlan2_heatmap.{{level}}_top{{topN}}.log",
    shadow:
        "shallow"
    conda:
        "../../envs/stag-mwc.yaml"
    threads:
        1
    params:
        outfile_prefix=lambda w: f"{OUTDIR}/metaphlan2/all_samples",
        pseudocount=mpa_config["heatmap"]["pseudocount"],
        colormap=mpa_config["heatmap"]["colormap"],
        method=mpa_config["heatmap"]["method"],
        metric=mpa_config["heatmap"]["metric"],
        extra=mpa_config["heatmap"]["extra"],
    shell:
        """
        scripts/plot_metaphlan2_heatmap.py \
            --outfile-prefix {params.outfile_prefix} \
            --level {wildcards.level} \
            --topN {wildcards.topN} \
            --pseudocount {params.pseudocount} \
            --colormap {params.colormap} \
            --method {params.method} \
            --metric {params.metric} \
            --force \
            {input} \
            2> {log}
        """

rule create_metaphlan2_krona_plots:
    input:
        expand(str(OUTDIR/"metaphlan2/{sample}.metaphlan2.krona"), sample=SAMPLES)
    output:
        html=report(OUTDIR/"metaphlan2/all_samples.metaphlan2.krona.html",
                    category="Taxonomic profiling",
                    caption="../../report/metaphlan2_krona.rst"),
    shadow:
        "shallow"
    conda:
        "../../envs/metaphlan2.yaml"
    threads:
        1
    shell:
        """
        ktImportText \
            -o {output.html} \
            {input}
        """
