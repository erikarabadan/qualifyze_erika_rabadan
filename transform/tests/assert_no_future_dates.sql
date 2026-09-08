select 'eudra' as source, certificate_number as id, issue_date as flagged_date
from {{ ref('stg_eudra_gmp') }}
where issue_date > current_date or inspection_end_date > current_date

union all

select 'audit' as source, audit_id as id, audit_date as flagged_date
from {{ ref('stg_audits') }}
where audit_date > current_date