{{ config(materialized='table') }}

with document_counts as (

    select
        site_id,
        count(*) as document_count,
        count(*) filter (where document_type = 'GMPNC') as active_ncr_count
    from {{ ref('eudra_sites_matches') }}
    where site_id is not null
    group by site_id

),

audit_counts as (

    select
        site_id,
        count(*) as audit_count
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
    coalesce(dc.document_count, 0) as document_count,
    coalesce(dc.active_ncr_count, 0) as active_ncr_count,
    coalesce(ac.audit_count, 0) as audit_count,
    case
        when coalesce(dc.active_ncr_count, 0) > 0 then 'non_compliant'
        when coalesce(dc.document_count, 0) = 0 then 'unknown'
        else 'compliant'
    end as compliance_status
from {{ ref('stg_sitesdb') }} s
left join document_counts dc on dc.site_id = s.site_id
left join audit_counts ac on ac.site_id = s.site_id