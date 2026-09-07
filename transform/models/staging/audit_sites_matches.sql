with exact as (

    select
        a.audit_id,
        a.site_name as audit_site_name,
        a.site_name_normalized,
        a.site_address as audit_site_address,
        a.site_address_normalized,
        a.site_city,
        a.site_country,
        s.site_id as exact_site_id
    from {{ ref('stg_audits') }} a
    left join {{ ref('stg_sitesdb') }} s
        on a.site_name_normalized = s.site_name_normalized
       and a.site_address_normalized = s.address_normalized

),

fuzzy_candidates as (

    select
        e.audit_id,
        s.site_id as resolved_site_id,
        similarity(e.site_name_normalized, s.site_name_normalized) as name_score,
        similarity(e.site_address_normalized, s.address_normalized) as address_score
    from exact e
    join {{ ref('stg_sitesdb') }} s
        on lower(e.site_city) = lower(s.city)
       and lower(e.site_country) = lower(s.country)
    where e.exact_site_id is null

),

fuzzy_best as (

    select *,
        least(name_score, address_score) as combined_score,
        row_number() over (partition by audit_id order by least(name_score, address_score) desc) as rn
    from fuzzy_candidates
    where least(name_score, address_score) >= 0.3

)

select
    e.audit_id,
    e.audit_site_name,
    e.audit_site_address,
    s.site_id,
    s.site_name,
    s.address as site_address,
    case
        when e.exact_site_id is not null then 'exact_name'
        when fb.resolved_site_id is not null then 'fuzzy_combined'
        else 'no match found'
    end as match_method,
    case when e.exact_site_id is not null then 1.0 else round(fb.name_score::numeric, 2) end as name_score,
    case when e.exact_site_id is not null then 1.0 else round(fb.address_score::numeric, 2) end as address_score
from exact e
left join fuzzy_best fb on fb.audit_id = e.audit_id and fb.rn = 1
left join {{ ref('stg_sitesdb') }} s on s.site_id = coalesce(e.exact_site_id, fb.resolved_site_id)
order by match_method, e.audit_id