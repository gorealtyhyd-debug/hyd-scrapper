# Tasks

## 1. Database foundation and shared identity

- [x] 1.1 Create the Supabase/PostgreSQL migration structure, UUID/timestamp helpers, and shared reference conventions; verify a clean database applies the foundation migration.
- [x] 1.2 Add source, document-type, property-type, listing-type, listing-status, party-role, lead-status, and access-role reference values; verify seeds are repeatable and invalid values are rejected.
- [x] 1.3 Add geographic hierarchy and scoped survey identifier/alias tables; verify identical survey labels in different village/SRO contexts remain distinct and aliases retain provenance.

## 2. Canonical properties, projects, and listings

- [x] 2.1 Implement development projects, phases, and canonical property identity with extensible type details; verify apartments/flats, villas, and plots can be modeled and unknown source types remain ingestible.
- [x] 2.2 Add property-to-project/phase and property-to-geography relationships with appropriate foreign keys and uniqueness rules; verify distinct units/parcels remain distinct and invalid links are rejected.
- [x] 2.3 Implement separate sale/rental listing lifecycle records with source, price fields, availability, and status history; verify multiple sequential listings can reference one property without changing its legal history.
- [x] 2.4 Add focused schema tests and relationship documentation for project, phase, property, survey, and listing identities; verify examples apply to a clean database.

## 3. Source observations and SRO ingestion

- [x] 3.1 Implement source profiles, import runs, and immutable source-observation/staging records with raw payload, source identity, observed/fetched timestamps, parser version, and source version; verify duplicate source versions are idempotent and changed versions remain traceable.
- [x] 3.2 Define and test SRO document identity using SRO and available year/book/document identifiers, keeping schedule identity separate; verify replayed rows do not create duplicate documents.
- [x] 3.3 Implement historical backfill and daily ingestion through the same staging/reconciliation path; verify a historical range can be replayed and a new daily record is added once.
- [x] 3.4 Add parser/import validation reports for missing identifiers, malformed dates/values, and source corrections; verify invalid observations are retained with an actionable status rather than silently discarded.

## 4. Registration history, schedules, and matching

- [x] 4.1 Implement registration documents and document schedules, preserving every received document type and raw schedule description; verify one document can have multiple schedules.
- [x] 4.2 Implement reusable parties and document-party relationships with exact source role codes; verify multiple parties and repeated parties across documents are represented without inferring ownership.
- [x] 4.3 Implement schedule-to-property match records with match method, confidence, and review state; verify one schedule can link to multiple properties and uncertain matches remain unresolved.
- [x] 4.4 Implement explicit document relationships and a property-history read ordered by registration date; verify mortgages, releases, rectifications, and other document types appear without being mislabeled as sales.
- [x] 4.5 Add focused tests and schema documentation for source identity, schedules, party roles, ambiguous matches, and property timelines; verify the documented scenarios against a clean database.

## 5. RERA project and phase data

- [x] 5.1 Implement sourced RERA registrations and observations linked to projects or phases, including status, dates, source identity, and history; verify RERA IDs remain distinct from SRO document IDs.
- [x] 5.2 Add RERA-to-development matching and review state; verify uncertain matches remain pending and missing records do not imply legal status.
- [x] 5.3 Add tests and documentation for project/phase registration links and property inheritance through project relationships; verify properties expose the applicable RERA context without duplicated unit-level registrations.

## 6. CRM lifecycle, audit, and access control

- [x] 6.1 Implement contacts, mobile captures, leads, follow-ups, and status-history records linked to canonical properties; verify qualification transitions append actor/time history.
- [x] 6.2 Implement internal users, role/permission mappings, and project/property assignments; verify assignment uniqueness and invalid references are rejected.
- [x] 6.3 Enable RLS and restricted views/RPCs for admin, telecaller, sales, and third-party access; verify assigned and unassigned records and sensitive source/CRM fields follow policy.
- [x] 6.4 Implement append-only audit events for identity matches, source promotion, listing lifecycle, CRM state, and assignment changes; verify audit evidence remains after archival.
- [x] 6.5 Add focused policy, audit, and CRM tests and access-matrix documentation; verify authenticated test identities cannot bypass database policies.

## 7. Analytics reads and end-to-end validation

- [x] 7.1 Implement curated property profile, property document history, current listing, and project/RERA reads; verify each includes source provenance and appropriate access filtering.
- [x] 7.2 Implement documented document-type classification and sale-trend aggregates that distinguish recorded consideration/market value from qualifying sale events; verify mortgage, release, and rectification records are excluded from sale trends.
- [x] 7.3 Add source coverage and classification context to analytics reads; verify consumers can identify time range, SRO/source coverage, and included document categories.
- [x] 7.4 Run migrations, import replay, relationship, analytics, and RLS tests against a clean PostgreSQL/Supabase environment; verify end-to-end historical backfill and daily ingestion behavior.
- [x] 7.5 Document migration order, backfill/reconciliation operations, rollback checkpoints, schema relationships, and field-level access; verify documented commands and paths match the repository.

## 8. MVP owner contact and intent workflow

- [x] 8.1 Add contact-method source evidence and property-scoped contact/party match records with candidate, confirmed, and rejected states; verify source provenance survives review changes and candidate numbers are not exposed as confirmed owners.
- [x] 8.2 Add independent sale and rent owner-intent tracks with qualification status and expected amount; verify the same property/contact can have both tracks and each changes independently.
- [x] 8.3 Add append-only call attempts and intent status history with actor/time/outcome, plus assignment-based RLS and audit policies; verify an unanswered call does not alter the other intent track or create a listing.
- [x] 8.4 Add focused tests and update schema/access documentation for external phone sources, reviewed owner matches, separate intent tracks, call outcomes, and listing handoff; verify the documented workflow against a clean PostgreSQL database.