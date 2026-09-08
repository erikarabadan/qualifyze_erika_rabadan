with exact as (

    select
        a.audit_id,
        a.audit_date,
        a.standard,
        a.auditee_company,
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

fuzzy_best as (

    select
        ex.audit_id,
        s.site_id as resolved_site_id,
        similarity(ex.site_name_normalized, s.site_name_normalized) as name_score,
        similarity(ex.site_address_normalized, s.address_normalized) as address_score,
        row_number() over (
            partition by ex.audit_id
            order by least(similarity(ex.site_name_normalized, s.site_name_normalized),
                            similarity(ex.site_address_normalized, s.address_normalized)) desc
        ) as rn
    from exact ex
    join {{ ref('stg_sitesdb') }} s
        on lower(ex.site_city) = lower(s.city)
       and lower(ex.site_country) = lower(s.country)
    where ex.exact_site_id is null

)

select
    ex.audit_id,
    ex.audit_date,
    ex.standard,
    ex.auditee_company,
    ex.audit_site_name,
    ex.audit_site_address,
    ex.site_city as audit_site_city,
    ex.site_country as audit_site_country,
    s.site_id,
    s.site_name,
    s.address as site_address,
    s.city as site_city,
    s.country as site_country,
    s.status as site_status,
    case
        when ex.exact_site_id is not null then 'exact_name'
        when fb.rn = 1 and least(fb.name_score, fb.address_score) >= 0.3 then 'fuzzy_combined'
        else 'no match found'
    end as match_method,
    coalesce(round(fb.name_score::numeric, 2), 1.0) as name_score,
    coalesce(round(fb.address_score::numeric, 2), 1.0) as address_score
from exact ex
left join fuzzy_best fb on fb.audit_id = ex.audit_id and fb.rn = 1
left join {{ ref('stg_sitesdb') }} s on s.site_id = coalesce(ex.exact_site_id, fb.resolved_site_id)
order by match_method, ex.audit_id