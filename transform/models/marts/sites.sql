{{ config(materialized='table') }}

with document_summary as (

    select
        site_id,
        true as has_any_document,
        bool_or(document_type = 'GMPNC') as has_active_ncr
    from {{ ref('eudra_sites_matches') }}
    where site_id is not null
    group by site_id

),

audit_summary as (

    select
        site_id,
        true as has_any_audit
    from {{ ref('audit_sites_matches') }}
    where site_id is not null
    group by site_id

)

select
    s.site_id,
    s.site_name,
    s.address,
    s.city,
    s.country,
    s.country_code,
    s.status,
    coalesce(ds.has_any_document, false) as has_any_document,
    coalesce(ds.has_active_ncr, false) as has_active_ncr,
    coalesce(aud.has_any_audit, false) as has_any_audit
from {{ ref('stg_sitesdb') }} s
left join document_summary ds on ds.site_id = s.site_id
left join audit_summary aud on aud.site_id = s.site_id