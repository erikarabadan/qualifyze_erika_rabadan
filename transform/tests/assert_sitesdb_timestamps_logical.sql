select site_id, created_at, updated_at
from {{ ref('stg_sitesdb') }}
where updated_at < created_at