select certificate_number, inspection_end_date, issue_date
from {{ ref('stg_eudra_gmp') }}
where issue_date < inspection_end_date