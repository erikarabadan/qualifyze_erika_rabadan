-- Every newentityreferenceid should point to a row that is ITSELF canonical
-- (i.e. its own newentityreferenceid is null). If this ever returns rows,
-- SitesDB has a duplicate chain deeper than one hop, and the dedup logic
-- in stg_sitesdb would need to be revisited (currently assumes one hop only).
select
    d.siteid as duplicate_site_id,
    d.newentityreferenceid as points_to,
    t.newentityreferenceid as target_also_points_to
from {{ source('raw', 'sitesdb') }} d
left join {{ source('raw', 'sitesdb') }} t
    on t.siteid = d.newentityreferenceid
where d.newentityreferenceid is not null
  and (t.siteid is null or t.newentityreferenceid is not null)