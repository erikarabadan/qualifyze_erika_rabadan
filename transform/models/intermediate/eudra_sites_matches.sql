{{ config(materialized='table') }}

with exact as (

    select
        e.certificate_number,
        e.document_type,
        e.mia_number,
        e.site_nca_reference,
        e.issue_date,
        e.inspection_end_date,
        e.last_updated_date,
        e.site_name as eudra_site_name,
        e.site_name_normalized,
        e.address_1 as eudra_address,
        e.address_1_normalized,
        e.city as eudra_city,
        e.country as eudra_country,
        s.site_id as exact_site_id
    from {{ ref('stg_eudra_gmp') }} e
    left join {{ ref('stg_sitesdb') }} s
        on upper(e.site_name_normalized) = upper(s.site_name_normalized)
       and upper(e.address_1_normalized) = upper(s.address_normalized)

),

fuzzy_candidates as (

    select
        ex.certificate_number,
        s.site_id as resolved_site_id,
        similarity(ex.site_name_normalized, s.site_name_normalized) as name_score,
        similarity(ex.address_1_normalized, s.address_normalized) as address_score,
        ex.eudra_city is null as matched_without_city
    from exact ex
    join {{ ref('stg_sitesdb') }} s
        on upper(ex.eudra_country) = upper(s.country)
       and (ex.eudra_city is null or upper(ex.eudra_city) = upper(s.city))
    where ex.exact_site_id is null

),

fuzzy_best as (

    select *,
        row_number() over (
            partition by certificate_number
            order by least(name_score, address_score) desc
        ) as rn
    from fuzzy_candidates
    where least(name_score, address_score) >= 0.3

)

select
    ex.certificate_number,
    ex.document_type,
    ex.mia_number,
    ex.site_nca_reference,
    ex.issue_date,
    ex.inspection_end_date,
    ex.last_updated_date,
    ex.eudra_site_name,
    ex.eudra_address,
    ex.eudra_city,
    ex.eudra_country,
    s.site_id,
    s.site_name,
    s.address as site_address,
    s.city as site_city,
    s.country as site_country,
    s.status as site_status,
    case
        when ex.exact_site_id is not null then 'exact_name'
        when fb.rn = 1 and fb.matched_without_city then 'fuzzy_no_city_confirmation'
        when fb.rn = 1 then 'fuzzy_combined'
        else 'no match found'
    end as match_method,
    case when ex.exact_site_id is not null then 1.0 else round(fb.name_score::numeric, 2) end as name_score,
    case when ex.exact_site_id is not null then 1.0 else round(fb.address_score::numeric, 2) end as address_score
from exact ex
left join fuzzy_best fb on fb.certificate_number = ex.certificate_number and fb.rn = 1
left join {{ ref('stg_sitesdb') }} s on s.site_id = coalesce(ex.exact_site_id, fb.resolved_site_id)
order by document_type desc, match_method, ex.certificate_number