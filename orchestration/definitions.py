import subprocess
from pathlib import Path
from dagster import asset, define_asset_job, ScheduleDefinition, Definitions, AssetExecutionContext

PROJECT_ROOT = Path(__file__).resolve().parent.parent


@asset
def raw_tables(context: AssetExecutionContext):
    """Loads the 3 source Excel/xls files into raw.* Postgres tables."""
    result = subprocess.run(
        ["python", "ingestion/load_raw.py"],
        cwd=PROJECT_ROOT,
        capture_output=True, text=True,
    )
    context.log.info(result.stdout)
    if result.returncode != 0:
        raise Exception(f"load_raw.py failed:\n{result.stderr}")


@asset(deps=[raw_tables])
def dbt_models(context: AssetExecutionContext):
    """Runs staging -> intermediate -> marts via dbt build.
    Uses `dbt build` so a failing test blocks downstream models."""
    result = subprocess.run(
        ["dbt", "build"],
        cwd=PROJECT_ROOT / "transform",
        capture_output=True, text=True,
    )
    context.log.info(result.stdout)
    if result.returncode != 0:
        raise Exception(f"dbt build failed:\n{result.stderr}")


pipeline_job = define_asset_job("qualifyze_pipeline", selection=[raw_tables, dbt_models])

daily_schedule = ScheduleDefinition(
    job=pipeline_job,
    cron_schedule="0 6 * * *",
)

defs = Definitions(
    assets=[raw_tables, dbt_models],
    jobs=[pipeline_job],
    schedules=[daily_schedule],
)