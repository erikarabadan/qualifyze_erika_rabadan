create schema if not exists raw;

create table if not exists raw.sitesdb (
    siteid text, sitename text, address text, zip text, city text,
    countrycode text, country text, status text, isdeleted text,
    newentityreferenceid text, createdat text, updatedat text,
    _source_file text not null,
    _load_batch_id uuid not null,
    _loaded_at timestamptz not null default now()
);

create table if not exists raw.audits (
    auditid text, auditdate text, standard text, auditeecompany text,
    sitename text, siteaddress text, sitecity text, sitecountry text,
    _source_file text not null,
    _load_batch_id uuid not null,
    _loaded_at timestamptz not null default now()
);

create table if not exists raw.eudra_gmp (
    certificate_number text, eudragmdp_document_reference_number text,
    document_type text, mia_number text, oms_organisation_identifier text,
    oms_location_identifier text, site_name text,
    address_1 text, address_2 text, address_3 text, address_4 text,
    city text, postcode text, country text, duns_number text,
    site_nca_reference text, inspection_end_date text,
    issue_date text, last_updated_date text,
    _source_file text not null,
    _load_batch_id uuid not null,
    _loaded_at timestamptz not null default now()
);