import os
import json
import pathlib
import subprocess
import tempfile

from jinja2 import Template


# directories
data_dir = pathlib.Path(config['directories']['data'])
log_dir = pathlib.Path(config['directories']['log'])

# wildcards
wc_params = {k: v.split('|') for k, v in config['wildcards'].items()}

# etl config
models_path = workflow.source_path('../../config/models.json')
with open(models_path, 'r') as f:
    models = json.load(f)


class DuckDB:
    """Run SQL-based transforms from a template using DuckDB."""

    def __call__(self, path):
        cmd = [self.exe, '-init', self.rc, '-c ".read', path, '"']
        subprocess.run(' '.join(cmd), shell=True, check=True)

    @classmethod
    def from_template(cls, template, params, log=None):
        duckdb = cls()
        sql = duckdb.write_sql(template, params)
        if log:
            with open(log, 'w') as f:
                f.write(sql)
        with tempfile.NamedTemporaryFile(mode='w+', suffix='.sql', delete=True) as f:
            f.write(sql)
            f.flush()
            duckdb(f.name)

    @property
    def rc(self):
        return workflow.source_path('../../config/duckdbrc-slurm')

    @property
    def exe(self):
        return (pathlib.Path(os.environ['GROUP_HOME']) / 'opt/duckdb/1.0.0').as_posix()

    @staticmethod
    def write_sql(template, params):
        with open(template) as f:
            t = Template(f.read())
        return t.render(params)


transform = DuckDB.from_template
"""Convenience function for running dynamically generated SQL scripts for ETL using DuckDB."""