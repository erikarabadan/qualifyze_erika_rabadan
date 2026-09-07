with base as (

    select
        siteid::uuid as site_id,
        trim(sitename) as site_name,
        {{ normalize_text('sitename') }} as site_name_normalized,
        trim(address) as address,
        {{ normalize_text('address') }} as address_normalized,
        nullif(trim(zip), '') as postal_code,
        trim(city) as city,
        upper(trim(countrycode)) as country_code,
        trim(country) as country,
        status,
        isdeleted::boolean as is_deleted,
        createdat::timestamp as created_at,
        updatedat::timestamp as updated_at
    from {{ source('raw', 'sitesdb') }}
    where newentityreferenceid is null

)

select distinct on (site_name_normalized, address_normalized)
    site_id, site_name, site_name_normalized, address, address_normalized,
    postal_code, city, country_code, country, status, is_deleted, created_at, updated_at
from base
where is_deleted = false
order by site_name_normalized, address_normalized, updated_at desc, site_id