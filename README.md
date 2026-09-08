# Qualifyze Data Pipeline — Staff Data Engineer Technical Case

## Overview
This pipeline ingests EudraGMDP (public EU GMP compliance data), SitesDB
(Qualifyze's internal site master), and audit records, resolves them to a
single canonical notion of "site," and produces backend-consumable marts
answering: which sites are compliant, what documentation and audit history
exists per site, and where visibility gaps remain.

## Assumptions
- **SitesDB duplicate resolution**: a row is canonical if `newentityreferenceid`
  is null; duplicates are excluded via this field, `isdeleted`, and a
  `distinct on (name, address)` safety net. Testing surfaced 3 duplicate
  pairs SitesDB's own dedup mechanism missed entirely (no reference link
  set on either row) — caught only by additionally filtering `isdeleted`.
- **Match key**: sites are matched to EudraGMDP/audit records via normalized
  (name, address), scoped to city+country. Address alone is insufficient —
  two distinct real companies (OPTOPAN, PROTINA) share 3 physical addresses
  in Ismaning, confirmed by EudraGMDP's own distinct OMS Location IDs.
- **Fuzzy match confidence**: uses `least(name_similarity, address_similarity)`,
  not `greatest()` — a match requires BOTH signals to agree. `greatest()` was
  tested first and found to produce false positives (the Ismaning case).
  Threshold of 0.3 (on `least`) was empirically validated against this
  dataset's real score distribution, not assumed.
- **Compliance definition**: a site is `is_compliant = false` only if it has
  at least one matched GMPNC. The data provides no expiry/supersession
  signal, so every GMPC is treated as currently valid.
- **Unmatched records are kept, not dropped**: intermediate matching tables
  retain `no match found` rows for full auditability; marts filter to
  matched-only rows (fact tables) or include all sites regardless of
  activity (dimension table), per each table's own grain.
- **EudraGMDP vs SitesDB coverage gap is expected, not a bug**: most
  unmatched EudraGMDP documents have no SitesDB site in the same
  city+country at all — consistent with EudraGMDP's broader public scope
  vs. SitesDB's internally-tracked scope.
- One audit record has a null site address — a genuinely incomplete
  source record, not a pipeline defect. Matching logic resolves this
  gracefully to `no match found`; the staging test is `severity: warn`.

## Architecture

    Excel files (data/)
            |
       [Python: ingestion/load_raw.py]
            |
            v
      raw.*  (Postgres, all-text, truncate+reload per run)
            |
       [dbt: staging models]
            |
            v
      staging.*  (typed, cleaned, 1:1 with source, normalized text columns)
            |
       [dbt: