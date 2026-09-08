select 'audits row count mismatch' as issue,
       (select count(*) from {{ ref('stg_audits') }}) as staging_count,
       (select count(*) from {{ ref('audit_sites_matches') }}) as intermediate_count
where (select count(*) from {{ ref('stg_audits') }}) != (select count(*) from {{ ref('audit_sites_matches') }})