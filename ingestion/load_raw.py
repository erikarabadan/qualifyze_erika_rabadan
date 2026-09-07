import uuid
from pathlib import Path

import pandas as pd
from sqlalchemy import create_engine, text

DB_URL = "postgresql+psycopg2://qualifyze:qualifyze@localhost:5432/qualifyze"
DATA_DIR = Path(__file__).resolve().parent.parent / "data"

engine = create_engine(DB_URL)
batch_id = str(uuid.uuid4())


def find_header_row(path):
    # the eudra export has a few junk rows on top (title, "Total Records: N, <date>")
    # before the actual header - just scan for it instead of hardcoding row 4
    preview = pd.read_excel(path, header=None, nrows=15)
    for i, row in preview.iterrows():
        if str(row.iloc[0]).strip() == "Certificate Number":
            return i
    raise ValueError("couldn't find the header row in " + str(path))


def load_sitesdb():
    df = pd.read_excel(DATA_DIR / "sitesdb_export.xlsx", dtype=str)
    df["_source_file"] = "sitesdb_export.xlsx"
    df["_load_batch_id"] = batch_id

    with engine.begin() as conn:
        conn.execute(text("truncate table raw.sitesdb"))
        df.to_sql("sitesdb", conn, schema="raw", if_exists="append", index=False)

    return len(df)


def load_audits():
    df = pd.read_excel(DATA_DIR / "audits.xlsx", dtype=str)
    df["_source_file"] = "audits.xlsx"
    df["_load_batch_id"] = batch_id

    with engine.begin() as conn:
        conn.execute(text("truncate table raw.audits"))
        df.to_sql("audits", conn, schema="raw", if_exists="append", index=False)

    return len(df)


def load_eudra():
    path = DATA_DIR / "eudra_gmp_export.xls"
    header_row = find_header_row(path)

    df = pd.read_excel(path, header=header_row, dtype=str)
    df.columns = [c.strip() for c in df.columns]

    # spreadsheet headers are "Title Case With Spaces", renaming to snake_case
    # so we don't have to quote every column name in sql later
    df = df.rename(columns={
        "Certificate Number": "certificate_number",
        "EudraGMDP Document Reference Number": "eudragmdp_document_reference_number",
        "Document Type": "document_type",
        "MIA Number": "mia_number",
        "OMS Organisation Identifier": "oms_organisation_identifier",
        "OMS Location Identifier": "oms_location_identifier",
        "Site Name": "site_name",
        "Address 1": "address_1",
        "Address 2": "address_2",
        "Address 3": "address_3",
        "Address 4": "address_4",
        "City": "city",
        "Postcode": "postcode",
        "Country": "country",
        "DUNS Number": "duns_number",
        "Site NCA Reference": "site_nca_reference",
        "Inspection End Date": "inspection_end_date",
        "Issue Date": "issue_date",
        "Last Updated Date": "last_updated_date",
    })

    df = df.dropna(how="all")  # a couple of trailing blank rows show up in these exports
    df["_source_file"] = "eudra_gmp_export.xls"
    df["_load_batch_id"] = batch_id

    with engine.begin() as conn:
        conn.execute(text("truncate table raw.eudra_gmp"))
        df.to_sql("eudra_gmp", conn, schema="raw", if_exists="append", index=False)

    return len(df)


if __name__ == "__main__":
    counts = {
        "sitesdb": load_sitesdb(),
        "audits": load_audits(),
        "eudra_gmp": load_eudra(),
    }
    print(f"batch {batch_id}")
    print(counts)