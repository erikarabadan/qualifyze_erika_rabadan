{{ config(materialized='table') }}

with eudra_sites as (

    select distinct site_id
    from {{ ref('eudra_sites_matches') }}
    where site_id is not null

),

audit_sites as (

    select distinct site_id
    from {{ ref('audit_sites_matches') }}
    where site_id is not null

),

quiet_sites as (

    select s.site_id
    from {{ ref('sites') }} s
    left join eudra_sites es on es.site_id = s.site_id
    left join audit_sites aus on aus.site_id = s.site_id
    where es.site_id is null
      and aus.site_id is null

)

select
    s.site_id,
    s.site_name,
    s.address,
    s.city,
    s.country,
    s.status,
    s.compliance_status,
    'eudra' as source,
    e.certificate_number as reference_id,
    e.document_type as activity_detail,
    e.issue_date as activity_date,
    e.match_method,
    e.name_score,
    e.address_score
from {{ ref('sites') }} s
join {{ ref('eudra_sites_matches') }} e on e.site_id = s.site_id

union all

select
    s.site_id,
    s.site_name,
    s.address,
    s.city,
    s.country,
    s.status,
    s.compliance_status,
    'audit' as source,
    a.audit_id as reference_id,
    a.standard as activity_detail,
    a.audit_date as activity_date,
    a.match_method,
    a.name_score,
    a.address_score
from {{ ref('sites') }} s
join {{ ref('audit_sites_matches') }} a on a.site_id = s.site_id

union all

select
    s.site_id,
    s.site_name,
    s.address,
    s.city,
    s.country,
    s.status,
    s.compliance_status,
    'none' as source,
    null as reference_id,
    null as activity_detail,
    null as activity_date,
    null as match_method,
    null as name_score,
    null as address_score
from {{ ref('sites') }} s
join quiet_sites q on q.site_id = s.site_id