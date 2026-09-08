{{ config(materialized='table') }}

select
    s.site_id,
    s.site_name,
    s.address as site_address,
    s.city as site_city,
    s.country as site_country,
    s.status as site_status,
    m.audit_id,
    m.audit_date,
    m.standard,
    m.auditee_company,
    m.match_method,
    m.name_score,
    m.address_score
from {{ ref('sites') }} s
join {{ ref('audit_sites_matches') }} m
    on m.site_id = s.site_id