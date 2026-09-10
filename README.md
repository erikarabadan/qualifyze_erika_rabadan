# Qualifyze Data Pipeline — Staff Data Engineer Technical Case

## Overview

This pipeline ingests EudraGMDP (public EU GMP compliance data), SitesDB (Qualifyze's internal site master), and audit records, resolves them to a single canonical notion of "site," and produces backend-consumable marts answering: which sites are compliant, what documentation and audit history exists per site, and where visibility gaps remain.

## Assumptions

- We rely on normalized **(name, address)** as a unique site identifier. This is a much stronger guarantee than address alone — validated directly by the Ismaning cluster, where two distinct companies (OPTOPAN, PROTINA) share 3 physical addresses but are correctly disambiguated by name. Two genuinely unrelated companies sharing both an identical registered name and an identical address is not a realistic risk this design needs to guard against.
- We assume EudraGMDP's `Country` values and SitesDB's `country` values use a consistent naming convention (both full English country names), allowing a direct text join without a country-code crosswalk table.
- We assume it is normal and expected for a site to have no matched EudraGMDP document, no matched audit, or neither — not an error condition. This shaped `compliance_status = 'unknown'` as a distinct, legitimate state rather than treating zero matches as a data quality failure to be minimized.
- **SitesDB duplicate resolution**: downstream consumers are assumed to only care about active (non-deleted) site status, so `stg_sitesdb` filters `is_deleted = false`. A row is otherwise canonical if `newentityreferenceid` is null, plus a `distinct on (name, address)` safety net. Testing surfaced 3 duplicate pairs SitesDB's own dedup mechanism missed entirely (no reference link set on either row) — only distinguishable from their canonical survivor by `isdeleted`, which is why the deleted-row filter matters for correctness, not just scope. Deleted rows remain queryable in `raw.sitesdb` if ever needed.
- We assume EudraGMDP and Qualifyze audits are independent signals about a site — a site can legitimately have one without the other, and neither implies the other. This is a domain assumption, not provable from the schema alone, though it's consistent with 5 of 8 `unknown`-status sites having audit history despite no EudraGMDP presence.
- **EudraGMDP's OMS identifier hierarchy was verified, not assumed**: every `OMS Organisation Identifier` uses exactly one `Site Name` string across all its documents, and every `OMS Location Identifier` belongs to exactly one organisation (zero exceptions across 34 organisations, 41 locations). This confirms organisation ≈ company name, location ≈ (company, address) — directly explaining why address alone is unsafe as a join key, and why matching uses the (name, address) composite instead. SitesDB does not model this org/location distinction, which is why an OMS-based join to SitesDB isn't possible at all.
- **Compliance definition reflects the most recent EudraGMDP document per site (by `issue_date`), not "has any GMPNC ever appeared."** A site is `non_compliant` if its latest document is a GMPNC, `unknown` if it has zero matched documents, else `compliant`. This dataset has no site with both a GMPC and GMPNC, so the distinction can't be validated against real data — but "any NCR ever" would incorrectly and permanently flag a site as non-compliant even after a later re-certifying GMPC.
- **`compliance_status` is site-level, not scope-level.** GMP certification is typically scoped to specific activities/products. `MIA Number` was checked as a possible scope-identifying field but ruled out: paired same-inspection certificates (e.g. Erlangen, LIT Leibniz, Yusen Logistics) share an identical `MIA Number`, and it's null in 13/45 rows overall. However, **NCRs and GMPCs are structurally different document types**: `MIA Number` is filled for 32/43 GMPCs but 0/2 GMPNCs; `Site NCA Reference` is filled for 19/43 GMPCs but 2/2 GMPNCs — a complete, consistent split at the document-type boundary. This supports NCRs being inherently site-level findings, consistent with computing `compliance_status` at the site level.
- Some sites have multiple simultaneous certificates (same site, same inspection date, same MIA) with no field distinguishing them beyond the certificate number itself — confirmed by inspecting every column for one such pair (Universitaetsklinikum Erlangen). This remains an unexplained pattern in the source data, not a solved one.
- **Unmatched records are kept, not dropped**: intermediate matching tables retain `no match found` rows for full auditability; marts filter to matched-only rows (fact tables) or include all sites regardless of activity (dimension table), per each table's own grain.
- **EudraGMDP vs SitesDB coverage gap is expected, not a bug**: of 35 resolved sites, 3 (MediPack France SAS, Benelux Cold Chain BV, Padana Pharma S.p.A.) have zero matched documents or audits. Verified by direct inspection: their countries either have no source records at all (France, Italy), or all same-country records belong to other, geographically distinct sites (Netherlands — Utrecht/Hulst/Geleen, not Amsterdam).
- **A distinct, more concerning gap type exists beyond the 3 known zero-activity sites**: sites with real EudraGMDP activity that SitesDB has never onboarded at all, invisible to `marts.sites` entirely since there's no row to attach an "unknown" status to. Confirmed example: Yusen Logistics (Benelux) B.V., Hulst, Netherlands — 2 active GMPC certificates in EudraGMDP, zero presence in SitesDB. Detectable only by comparing unmatched EudraGMDP site names directly against SitesDB, not from any mart output.
- Two source records have incomplete location data (one audit with a null address, one with a null city) — both genuinely incomplete in the source ("Unknown Contract Manufacturer" auditee), not pipeline defects. Matching logic resolves these gracefully via SQL null-propagation; corresponding staging tests are `severity: warn`, not blocking.

## Architecture

```
Excel files (data/)
        |
   [Python: ingestion/load_raw.py]
        |
        v
+-------------------+
|  raw.*            |  Postgres tables, all-text, truncate+reload
+---------+---------+
          |
   [dbt: staging models]
          |
+---------+-------------------------------+
|  staging.stg_audits      (table)        |
|  staging.stg_eudra_gmp   (table)        |
|  staging.stg_sitesdb     (table, dedup) |
+---------+-------------------------------+
          |
   [dbt: intermediate - matching/resolution]
          |
+---------+---------------------------------------+
|  intermediate.audit_sites_matches   (table)      |
|  intermediate.eudra_sites_matches   (table)      |
|  (fuzzy waterfall: exact -> fuzzy scoped by       |
|   city+country -> least(name,address) >= 0.3;    |
|   unmatched rows retained, not dropped)          |
+---------+---------------------------------------+
          |
   [dbt: marts - backend-facing]
          |
+---------+---------------------------------------+
|  marts.sites                   (table, dim, 35)  |
|  marts.sites_eudra             (table, fact)     |
|  marts.sites_audits            (table, fact)     |
|  marts.sites_compliance_status (table, feed)     |
+---------+---------------------------------------+
          |
          v
  Backend / product consumer

Orchestration: Dagster (raw_tables -> dbt_models asset chain),
daily schedule defined, not activated for this exercise.

Tests: dbt build (not run+test separately) - 9 test files,
fail-fast so a failing test blocks downstream rebuilds.
```

## Key design decisions and trade-offs

**Layered architecture (raw → staging → intermediate → marts).** Each layer has exactly one job. EudraGMDP display fields (issue_date, mia_number, etc.) are propagated directly into the matching model rather than joined back later — the matching model already scans `stg_eudra_gmp` in full, so adding columns there is free, whereas a second join at the mart layer would re-read the table unnecessarily.

**Matching is a waterfall: exact → fuzzy, never a single pass.**
1. Exact match on normalized (name, address).
2. Fuzzy fallback, scoped to same city+country (falls back to country-only when city is null — 2 known audit records have no recorded city).
3. Fuzzy score uses `least(name_similarity, address_similarity)`, not `greatest()`. `greatest()` was tried first and produced a false positive — OPTOPAN and PROTINA share 3 physical addresses in Ismaning; `greatest()` let a coincidental address match win regardless of a completely different company name.
4. Unmatched documents/audits are kept with `match_method = 'no match found'`, not dropped.

**Text normalization is centralized in a macro, applied once in staging.** `normalize_text()` is computed once per record as `_normalized` columns, not recomputed inline at every comparison.

**`dbt build`, not `dbt run` + `dbt test` separately.** Given this is compliance-adjacent data, test failures are treated as blocking — `dbt build` skips rebuilding whatever depends on a failed model.

**`compliance_status` is a 3-value status derived from the most recent document, not a boolean derived from "any NCR ever."** Computed via a single window-function pass — `row_number() over (partition by site_id order by issue_date desc)` — then aggregated with `max(case when rn = 1 then ... end)` to pull the top-ranked document's type/date alongside `count()`/`count() filter (...)` for volume, all in one scan.

**Match confidence scores (`name_score`, `address_score`) are exposed directly in `intermediate` and `marts` tables.** Deliberate for this exercise — scores were essential for manual validation (e.g. confirming a fuzzy match between "PROTINA Pharmazeutische GmbH" and "PROTINA Pharmazeutische GmbH & Co. KG" was correct via its 0.81/1.0 component scores). For a production API, I'd exclude these from the primary contract and expose them only via a separate audit/debug endpoint.

**Materialization: table everywhere, for simplicity.** All staging, intermediate, and mart models are dbt tables, not views. `stg_sitesdb` (dedup logic) and both `*_sites_matches` models (trigram similarity + window functions) are computationally expensive and referenced by multiple downstream models within a single run, so materializing avoids redundant recomputation. `stg_audits`/`stg_eudra_gmp` don't strictly need table materialization (simple casts, referenced once each), but were kept consistent with the rest for simplicity rather than mixing strategies per-model. Run cadence is currently manual (`dbt build`, or Dagster's "Materialize all"); a daily schedule is defined but not activated (see Known Limitations).

## Schema contract

### `marts.sites` (dimension — one row per resolved site, always 35 rows regardless of activity)

| column | type | notes |
|---|---|---|
| site_id | uuid | resolved SitesDB identifier (post-dedup) |
| site_name, address, city, country, country_code | text | |
| status | text | SitesDB's own workflow state — independent of `compliance_status`, can disagree with it |
| document_count | int | count of matched EudraGMDP documents (GMPC + GMPNC) |
| active_ncr_count | int | count of matched GMPNC specifically |
| audit_count | int | count of matched Qualifyze audits |
| latest_document_type, latest_document_date | text, date | most recent matched document, by issue_date |
| compliance_status | text | `compliant` / `non_compliant` (latest document is GMPNC) / `unknown` (zero matched documents — may still have audits) |

### `marts.sites_eudra` (fact — one row per matched EudraGMDP document; 30 rows: 25 exact + 5 fuzzy matches, out of 45 total documents)

| column | type | notes |
|---|---|---|
| certificate_number, document_type | | |
| mia_number, site_nca_reference | text | nullable — see assumptions re: NCR/GMPC structural difference |
| issue_date, inspection_end_date, last_updated_date | date | |
| site_id, site_name, site_address, site_city, site_country, site_status | | denormalized from `sites` |
| match_method | text | `exact_name` / `fuzzy_combined` / `fuzzy_no_city_confirmation` |
| name_score, address_score | numeric | see design decisions re: production exposure |

### `marts.sites_audits` (fact — same shape, one row per matched audit; 24 of 32 total audits matched)

| column | type | notes |
|---|---|---|
| audit_id, audit_date, standard, auditee_company | | |
| site_id, site_name, site_address, site_city, site_country, site_status | | |
| match_method, name_score, address_score | | |

### `marts.sites_compliance_status` (unified activity feed — 57 rows: 30 eudra + 24 audit + 3 quiet-site rows for sites with zero activity)

| column | type | notes |
|---|---|---|
| site_id, site_name, address, city, country, status, compliance_status | | |
| source | text | `'eudra'` / `'audit'` / `'none'` |
| reference_id | text | certificate_number or audit_id; null for `'none'` |
| activity_detail | text | document_type for eudra rows, standard for audit rows |
| activity_date, match_method, name_score, address_score | | null for `'none'` rows |

Answers "show me everything for site X" in one query, no joins required.

### Key semantics
- Unmatched records are retained in `intermediate.*` but excluded from `sites_eudra`/`sites_audits`.
- `compliance_status = 'unknown'` means no EudraGMDP data specifically — check `audit_count` separately (5 of 8 `unknown` sites have audits).
- A site with real EudraGMDP activity but no SitesDB presence at all (e.g. Yusen Logistics) will not appear anywhere in these marts.

## Setup and run instructions

**Requirements:** Docker Desktop, Python 3.10+.

1. Clone the repo, `cd` into it.
2. Start Postgres: `docker compose up -d`
3. Create the raw schema: `docker exec -i qualifyze_pg psql -U qualifyze -d qualifyze < sql/raw_schema.sql`
4. Set up Python (run each line in order):

```
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

5. Load raw data: `python ingestion/load_raw.py`
6. Enable the trigram extension (one-time): `docker exec -it qualifyze_pg psql -U qualifyze -d qualifyze -c "create extension if not exists pg_trgm;"`
7. Run the transformation pipeline:

```
cd transform
dbt build
```

8. (Optional) Explore orchestration via Dagster:

```
pip install dagster dagster-webserver
dagster dev -f orchestration/definitions.py
```

Open http://localhost:3000 and click "Materialize all."

**Troubleshooting:**
- If `python3 -m venv .venv` gives dbt compatibility errors (dbt requires
  Python 3.10+), your system's default `python3` may resolve to an older
  version. Check available versions with `ls /usr/local/bin/python3*`,
  then create the venv explicitly: `python3.13 -m venv .venv` (or
  whichever 3.10+ version is available).
- If pip fails installing `dbt-core-experimental-parser` with a
  `CERTIFICATE_VERIFY_FAILED` SSL error (common on fresh Python.org
  installs on Mac): `pip install --upgrade certifi && export
  SSL_CERT_FILE=$(python -m certifi)`, then retry the install.

**Verify it worked:**

```
select count(*) from raw.sitesdb;   -- 49
select count(*) from marts.sites;   -- 35
```

**A few example queries to confirm the pipeline produces meaningful output, not just row counts (all verified against live data):**

List of non-compliant sites:
```sql
select site_name, city, country, active_ncr_count, latest_document_date
from marts.sites
where compliance_status = 'non_compliant';
```
Expect 2 rows: FINECURE PHARMACEUTICALS LIMITED and PANACEA BIOTEC PHARMA LIMITED, each with `active_ncr_count = 1`.

Full activity/status for one specific site:
```sql
select *
from marts.sites_compliance_status
where site_name ilike '%panacea%'
order by activity_date desc;
```
Expect 5 rows: 1 EudraGMDP NCR (`source = 'eudra'`, `activity_detail = 'GMPNC'`) plus 4 Qualifyze audits spanning 2024 — a real example of `non_compliant` status coexisting with substantial audit history, exactly the kind of full picture this table exists to surface.

A site with genuinely zero activity (no documents, no audits):
```sql
select *
from marts.sites
where document_count = 0 and audit_count = 0;
```
Expect 3 rows: MediPack France SAS, Benelux Cold Chain BV, Padana Pharma S.p.A. — confirmed genuine coverage gaps, not matching failures (see Assumptions).

## Known limitations

- **NCR-to-specific-certificate supersession is not modeled** — no field links a GMPNC to the specific GMPC it revokes.
- **No history/audit trail for match decisions** — rerunning after a threshold change silently overwrites prior results.
- **Thresholds (0.3 on `least()`) validated against this dataset only** (32 audits, 45 documents) — not tested at scale.
- **No source freshness checks** — nothing currently surfaces a silently stale `raw.eudra_gmp`.
- **Match confidence scores are exposed directly in marts**, which a production consumer-facing API likely shouldn't require.
- **Dagster schedule defined but not activated**; orchestration not deployed anywhere.
- **Credentials are plaintext in `docker-compose.yml`/`profiles.yml`**.
- **Daily batch cadence is a genuine mismatch for the brief's NCR-promptness requirement** — see Ideas to Scale for the proposed fix.

## Ideas to improve and scale the solution

- **NCR promptness via a two-speed pipeline.** Add a second, cheap, frequently-triggered path specifically for new/changed EudraGMDP records, alongside the existing daily full-reconciliation job: detection via a Dagster sensor polling `Last Updated Date` (or ideally a webhook, not available from a static export), append/upsert ingestion instead of truncate+reload, and `materialized='incremental'` matching models so only new documents get scored. Trade-off: incremental matching can't guarantee a previously-unmatched document gets re-evaluated when a new site is later added — the daily full-reconciliation job closes that gap.
- **Match history / audit trail**: a `dbt snapshot` on the mart layer, or an append-only match-history table keyed by (document_id, run_date), to preserve "what did we believe on date X" — meaningful for a compliance dataset.
- **Incremental materialization at scale**: move the document/audit-volume-scaling layers (staging + matching) to `materialized='incremental'`. The site dimension and aggregate marts can stay full-rebuild indefinitely, since their size is bounded by site count, which grows far more slowly than document/audit count.
- **Fuzzy matching index**: a `gin` trigram index (`gin_trgm_ops` on normalized name/address columns) as the next lever once the city+country-scoped cross join stops being cheap at volume.
- **Bulk load path**: convert to CSV and use Postgres's `COPY` instead of pandas' `to_sql` — 1-2 orders of magnitude faster at scale.
- **Source freshness checks** via `dbt source freshness`.
- **Move match confidence scores off the primary schema contract**, exposing them only via a separate audit/debug endpoint in production.
- **Secrets management** in place of plaintext credentials, for any real deployment.
