select 'sites row count mismatch' as issue,
       (select count(*) from {{ ref('stg_sitesdb') }}) as staging_count,
       (select count(*) from {{ ref('sites') }}) as marts_count
where (select count(*) from {{ ref('stg_sitesdb') }}) != (select count(*) from {{ ref('sites') }})