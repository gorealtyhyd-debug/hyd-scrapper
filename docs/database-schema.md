# Property Database Overview

## Inventory Relationships

```text
development_project 1 --> many development_phases
development_project / development_phase --> many properties
geographic_area --> many development_projects and properties
property 1 --> many property_identifiers, aliases, and listings
survey_identifier many <--> many properties through property_survey_identifiers
```

`properties` is the canonical identity for an asset. Its `property_type_code`
supports apartments/flats, villas, plots, and future or unclassified source
types. `residential_unit_details` and `land_plot_details` hold type-specific
fields without requiring each property type to populate the same columns.

Project and phase names are display attributes, not permanent identifiers.
Source spellings belong in project/property aliases. Flat, unit, plot, and house
numbers belong in `property_identifiers`, scoped by available source, office,
geography, project, and phase context.

Survey numbers are scoped by registration office and village. Original values
are kept alongside normalized values; aliases and successor/subdivision links
preserve identifier history. A `property_survey_identifiers` row records the
match method, confidence, review state, and source evidence. Pending matches
must not be treated as confirmed parcel links.

Listings are independent records. A property's registration history does not
create an active sale or rental offer, and one property may have multiple
listing records over time.

## Read Example

Retrieve a property's reviewed survey references and active listings:

```sql
SELECT
  p.id AS property_id,
  p.display_name AS property_name,
  s.raw_identifier AS survey_number,
  l.listing_type_code,
  l.asking_price,
  l.currency_code
FROM public.properties AS p
JOIN public.property_survey_identifiers AS ps
  ON ps.property_id = p.id
 AND ps.match_status = 'accepted'
JOIN public.survey_identifiers AS s
  ON s.id = ps.survey_identifier_id
LEFT JOIN public.property_listings AS l
  ON l.property_id = p.id
 AND l.listing_status_code = 'active'
WHERE p.id = $1
ORDER BY s.normalized_identifier, l.listing_type_code;
```

## Registration History

`registration_documents` uses a source-scoped identity: SRO, registration year,
book number, and document number. `registration_schedules` is separate, so one
document can have several schedules. Every imported version remains connected
through `registration_document_observations` and
`registration_schedule_observations`; the latter preserves the original
property description and parsed details for that source version.

`registration_document_parties` keeps the raw party name and exact
`source_role_code` alongside the normalized party-role reference. A `party_id`
is optional until the source name is confidently matched to a reusable party.
Claimant or executant roles are source facts, not automatic ownership claims.

`registration_schedule_property_matches` records the match method, confidence,
review status, and evidence for each schedule-observation/property link. Only
accepted matches appear in `property_registration_history`; pending matches
remain available for review. That history includes every classified linked
instrument in registration-date order. `property_sale_events` is narrower and
includes only document types explicitly classified as sale events. Recorded
consideration and market value remain source values, not universal sale prices.

Document-to-document relationships such as rectifications, cancellations, or
releases are stored separately in `registration_document_relations`. They
supplement the timeline without replacing the original registrations.

The initial analytics classification marks `sale_deed` as a sale event.
Mortgage, deposit of title deeds, mortgage release, development agreement,
gift, lease, rectification, cancellation, and unclassified `other` records are
not sale events by default. Classifications are reference data and must be
updated deliberately if a new qualifying document category is introduced.

Retrieve the accepted registration timeline for a property:

```sql
SELECT
  registration_year,
  book_no,
  document_no,
  document_type_as_recorded,
  registration_date,
  schedule_number,
  consideration_value,
  is_sale_event
FROM public.property_registration_history
WHERE property_id = $1
ORDER BY registration_date NULLS LAST, registration_year, book_no, document_no;
```

## RERA Relationships

RERA registration numbers are stored in `rera_registrations` and remain distinct
from SRO document identifiers. Each fetched status/project snapshot is retained
in `rera_registration_observations`; a missing status or registration record
means unknown or unavailable source data, not a legal conclusion.

`rera_project_matches` holds candidate project or phase links with match method,
confidence, evidence, and review status. Only one accepted match is allowed per
RERA registration. An accepted project-level match applies to that project's
properties; a phase-level match applies only to properties in that phase. The
`property_rera_registrations` view exposes the latest recorded observation only
through those accepted links.

## Access Matrix

Authenticated access is enforced in PostgreSQL, not only in portal filters.
Direct `SELECT` on `properties` is revoked; callers use role-filtered inventory
views. Sensitive registry/source tables are restricted to administrators and
trusted ingestion credentials.

| Role | Inventory | Listings | Leads and follow-ups | Source/party records | Mobile captures |
| --- | --- | --- | --- | --- | --- |
| Admin | All properties and details | All | All | Read and manage | Read and write |
| Telecaller | Assigned properties and details | Not granted | Assigned leads and owner-intent tracks | Assigned contact/party matches for assigned properties | Read/write assigned captures |
| Sales representative | Assigned properties and details | Assigned listings | Assigned resale/rent leads only | Not granted | Read/write assigned captures |
| Third party | Assigned safe projection only | Not granted | Not granted | Not granted | Write-only for assigned properties |

`property_inventory_projection` serves internal inventory roles;
`third_party_property_projection` returns a smaller assigned-property shape.
Third-party mobile inserts are restricted to the property and phone/source
fields, and the database supplies the authenticated actor. Third parties cannot
read the capture table or raw owner/party details. Audit events are append-only
and visible only to administrators.

## Owner Contact and Intent Workflow

External phone numbers are stored as CRM contact methods with one or more
`contact_method_sources` rows describing where and when each number was
collected and whether the evidence is still a candidate or has been verified.
`property_contact_matches` connects a number to a property and optionally to a
SRO party/document-party record. Candidate matches can be called for validation;
they are not displayed or treated as confirmed owner numbers until reviewed.

Each property/contact match can have separate `owner_intents` for `sale` and
`rent`. `workflow_status` describes the outreach/qualification state; it is not
the intent type. `owner_intent_call_attempts` records each call's actor, time,
outcome, and note, while `owner_intent_status_history` keeps status transitions.
A no-answer or callback on one track does not change the other. Confirmed intent
does not create a listing automatically; create or update the sale/rental
listing only after the corresponding offer details are verified.

## Analytics Definitions

`property_sale_trends_monthly` groups accepted, sale-classified documents by
registration month, geographic area, and property type. `sale_event_count` is a
count of distinct registration documents; average fields are calculated only
from non-null recorded values. `average_recorded_consideration` and
`average_recorded_market_value` are source amounts, not independently verified
market prices. `included_document_type_codes` and `source_sro_count` describe
the classification and coverage behind each aggregate.

`source_coverage_by_sro` reports source observation, promoted observation,
invalid observation, and promoted document counts plus registration-date span
and latest fetch time. Coverage reflects records successfully fetched by this
system; it does not assert that the SRO's underlying records are complete.

## Migration and Import Operations

Migrations are ordered SQL files under `supabase/migrations/`. Apply them to a
clean Supabase/PostgreSQL database before starting imports, in this dependency
order:

1. `20261005000100`–`20261005000200`: foundation helpers and reference catalogs.
2. `20261005000300`–`20261005000600`: geography, canonical properties, survey
  crosswalks, and listings.
3. `20261005000700`: import runs and immutable source observations.
4. `20261005000800`–`20261005001100`: registration documents, schedules,
  parties, reviewed property matches, and legal-history views.
5. `20261005001200`–`20261005001300`: RERA registrations and project/phase
  matching.
6. `20261005001400`–`20261005001700`: CRM workflows, users/assignments, RLS,
  and append-only audit events.
7. `20261005001800`: curated property, history, listing, trend, and coverage
  reads.
8. `20261005001900`: contact-source evidence, reviewed property-party matches,
  independent sale/rent intent tracks, and call-attempt history.

The SRO CSV loader uses `DATABASE_URL` from the environment and sends both
historical and daily files through the same staging, idempotency, validation,
and document-promotion path:

```sh
node scripts/import-sro-csv.mjs --file <csv-path> --mode historical_backfill
node scripts/import-sro-csv.mjs --file <csv-path> --mode daily
```

The loader stores original rows and validation reports. It does not create
canonical property links automatically; uncertain schedule/property matches
must be reviewed. Do not commit database credentials. Migrations are additive;
before a destructive schema change, disable ingestion and restore from a
database backup at the last verified checkpoint. Source observations and audit
history are retained during normal archival and must not be removed as part of
application rollback.

The local clean-database suite uses PGlite (PostgreSQL 18) with a minimal
Supabase Auth fixture:

```sh
node --test --test-concurrency=1 tests/database/*.test.mjs tests/ingestion/*.test.mjs
```