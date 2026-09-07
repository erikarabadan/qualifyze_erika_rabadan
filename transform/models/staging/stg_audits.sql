select
    auditid as audit_id,
    auditdate::date as audit_date,
    standard,
    trim(auditeecompany) as auditee_company,
    trim(sitename) as site_name,
    {{ normalize_text('sitename') }} as site_name_normalized,
    trim(siteaddress) as site_address,
    {{ normalize_text('siteaddress') }} as site_address_normalized,
    trim(sitecity) as site_city,
    trim(sitecountry) as site_country
from {{ source('raw', 'audits') }}