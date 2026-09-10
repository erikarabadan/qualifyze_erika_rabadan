{{ config(materialized='table') }}

with ranked_documents as (

    select
        site_id,
        document_type,
        issue_date,
        row_number() over (partition by site_id order by issue_date desc) as rn
    from {{ ref('eudra_sites_matches') }}
    where site_id is not null

),

document_summary as (

    select
        site_id,
        count(*) as document_count,
        count(*) filter (where document_type = 'GMPNC') as active_ncr_count,
        max(case when rn = 1 then document_type end) as latest_document_type,
        max(case when rn = 1 then issue_date end) as latest_document_date
    from ranked_documents
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
    coalesce(ds.document_count, 0) as document_count,
    coalesce(ds.active_ncr_count, 0) as active_ncr_count,
    coalesce(ac.audit_count, 0) as audit_count,
    ds.latest_document_type,
    ds.latest_document_date,
    case
        when ds.latest_document_type = 'GMPNC' then 'non_compliant'
        when ds.site_id is null then 'unknown'
        else 'compliant'
    end as compliance_status
from {{ ref('stg_sitesdb') }} s
left join document_summary ds on ds.site_id = s.site_id
left join audit_counts ac on ac.site_id = s.site_id