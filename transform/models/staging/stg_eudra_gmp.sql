{{ config(materialized='table') }}

select
    certificate_number,
    eudragmdp_document_reference_number as document_reference_number,
    document_type,
    nullif(trim(mia_number), '') as mia_number,
    oms_organisation_identifier as oms_org_id,
    oms_location_identifier as oms_location_id,
    trim(site_name) as site_name,
    {{ normalize_text('site_name') }} as site_name_normalized,
    trim(address_1) as address_1,
    {{ normalize_text('address_1') }} as address_1_normalized,
    nullif(trim(address_2), '') as address_2,
    nullif(trim(address_3), '') as address_3,
    nullif(trim(address_4), '') as address_4,
    trim(city) as city,
    nullif(trim(postcode), '') as postcode,
    trim(country) as country,
    nullif(trim(duns_number), '') as duns_number,
    nullif(trim(site_nca_reference), '') as site_nca_reference,
    inspection_end_date::date as inspection_end_date,
    issue_date::date as issue_date,
    last_updated_date::date as last_updated_date
from {{ source('raw', 'eudra_gmp') }}