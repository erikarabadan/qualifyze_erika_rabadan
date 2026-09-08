{{ config(materialized='table') }}

select
    s.site_id,
    s.site_name,
    s.address as site_address,
    s.city as site_city,
    s.country as site_country,
    s.status as site_status,
    m.certificate_number,
    m.document_type,
    m.mia_number,
    m.site_nca_reference,
    m.issue_date,
    m.inspection_end_date,
    m.last_updated_date,
    m.match_method,
    m.name_score,
    m.address_score
from {{ ref('sites') }} s
join {{ ref('eudra_sites_matches') }} m
    on m.site_id = s.site_id