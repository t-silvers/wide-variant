VCF_TEMPLATES = {
    'bactmap': 'data/variants/tool=bactmap/species={species}/family={family}/id={id}/library={library}/{sample}.filtered.vcf.gz',
    'legacy_mapping': 'data/variants/tool=legacy_mapping/species={species}/family={family}/id={id}/library={library}/{sample}.calls.view.vcf.gz',
    'snippy': 'data/variants/tool=snippy/species={species}/family={family}/id={id}/library={library}/{sample}.snps.vcf',
}


wildcard_constraints:
    ext='filtered.vcf.gz|calls.view.vcf.gz|snps.vcf',
    mapping_tool=config['tools']['mapping']


include: '../mapping-modules/bactmap.smk'
include: '../mapping-modules/legacy_mapping.smk'
include: '../mapping-modules/snippy.smk'


rule vcf_to_parquet:
    input:
        data_dir / 'results/{mapping_tool}/{species}/variants/{sample}.{ext}'
    output:
        data_dir / 'data/variants/tool={mapping_tool}/species={species}/family={family}/id={id}/library={library}/{sample}.{ext}.parquet',
    resources:
        cpus_per_task=4,
        runtime=5,
        njobs=1,
    envmodules:
        'vcf2parquet/0.4.1'
    shell:
        'vcf2parquet -i {input} convert -o {output}'


rule clean_vcf:
    input:
        data_dir / 'data/variants/tool={mapping_tool}/species={species}/family={family}/id={id}/library={library}/{sample}.{ext}.parquet',
    output:
        data_dir / 'data/variants/tool={mapping_tool}/species={species}/family={family}/id={id}/library={library}/{sample}.{ext}.cleaned.parquet',
    params:
        alt_density_window=config['mapping']['alt_density_window_half_size'],
        model=lambda wildcards: workflow.source_path(models['vcfs'][wildcards.mapping_tool]),
    resources:
        cpus_per_task=4,
        mem_mb=8_000,
        runtime=15,
        njobs=1,
    run:
        params.update({'input': input[0], 'output': output[0]})
        transform(params['model'], params)


def aggregate_vcfs(wildcards):
    import pandas as pd

    vcfs = [VCF_TEMPLATES[tool] for tool in config['tools']['mapping'].split('|')]

    def cleaned_vcf_pq(df):
        return '|'.join(list(map(lambda x: data_path_from_template(x + '.cleaned.parquet', df.to_dict()), vcfs)))

    return (
        pd.read_csv(
            checkpoints.reference_identification
            .get(**wildcards)
            .output[0]
        )
        .rename(columns={'reference_genome': 'species'})
        .dropna()
        .drop_duplicates()
        .transpose()
        .apply(lambda df: cleaned_vcf_pq(df))
        .str.split('|')
        .explode()
        .values
        .flatten()
    )


# PHONY
rule all_mapping:
    input:
        aggregate_vcfs
