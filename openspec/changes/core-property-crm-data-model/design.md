# Design

## Context

The repository currently contains source-specific scraping scripts and derived apartment CSV/JSON exports, but no database migrations, persistence service, authentication, or database policy layer. The attached SRO shape is document-oriented: a row has SRO/document identifiers, dates, document type, monetary values, party-role text, and a property description that can refer to apartments, flats, plots, houses, survey numbers, and schedules. The proposal and [property-crm-data-model spec](specs/property-crm-data-model/spec.md) define the expanded contract.

## Goals / Non-Goals

**Goals:**

- Establish a normalized Supabase/PostgreSQL schema with stable internal UUIDs and explicit foreign-key relationships for general properties, projects/phases, listings, registry history, RERA, and CRM.
- Preserve raw source observations separately from canonical entities and support idempotent SRO backfill from 2010 onward and daily ingestion.
- Make property/source matching, document identity, workflow state, assignments, and audit history traceable and enforceable.
- Support curated, source-aware property-history and analytics reads without coupling the database contract to a WhatsApp bot implementation.
- Provide an ordered migration and backfill path with review of ambiguous matches before canonical promotion.

**Non-Goals:**

- Implementing the Telangana scraper, scheduled jobs, CRM APIs, or frontend screens.
- Defining the final hosting or worker deployment topology.
- Building a general-purpose multi-tenant framework beyond the project/apartment assignment rules required by this CRM.

## Decisions

### Separate canonical properties, developments, and property types

Use a canonical property table with UUID identity and type-specific detail tables or constrained subtype records for apartments/flats, villas, houses, and plots. Model a development project and its phases separately from individual properties; relate units or parcels to the applicable project/phase. Keep administrative geography and survey identifiers separate, with survey identifiers scoped by SRO and village context and optional alias/successor relationships. Internal UUIDs remain stable when names or source identifiers change.

This avoids a flat-only schema and avoids storing every possible type-specific field in one sparse table. An unknown source property type can remain in the source-observation layer even before it is promoted to a fully modeled subtype.

### Treat source observations as immutable evidence and canonical data as reviewed identity

Store each fetched SRO or RERA record with source, source-scoped identity, raw values/payload, import-run identifier, observed/fetched timestamps, parser version, and source version or content hash where available. Enforce idempotency on the source's document identity (SRO plus available year, book, and document number); do not treat schedule number as a document-level identifier. Preserve repeated retrievals and changed source versions as traceable observations. Resolve observations to canonical entities through explicit match records that can carry method, confidence, and review status; uncertain matches remain unresolved rather than merging entities automatically.

Historical backfill and daily ingestion use the same identity and reconciliation rules. Parsing and canonical matching are separate so parser corrections can be replayed without losing original evidence.

### Model SRO documents, schedules, parties, and relations independently

Represent a registration document once per source identity, with one or more schedule rows. Keep raw property description and extracted location/survey/unit references on the schedule observation, then use a many-to-many schedule-property match table to connect it to canonical properties. A property-history view joins through these links. Model parties as reusable records with document-party relationships that retain the exact source role code and raw party text. Keep document-type classification and explicit document-to-document relations (such as rectification, cancellation, or release) separate from the original SRO description.

Do not infer legal ownership merely from a claimant role. Ownership or transaction interpretations are derived and qualified outputs, not replacements for source roles.

### Keep active listings distinct from legal events

Store sale and rental listings as lifecycle records linked to canonical properties. A listing carries the offer type, asking amount and currency/period, availability, source, and lifecycle dates/status. An SRO document contributes to legal history, never directly to current availability. Price analytics use explicit document-type classification rules and distinguish recorded market value and consideration from qualifying sale prices.

### Link RERA at development and phase level

Store RERA registrations as separately sourced, time-observed records linked to a development or phase. Properties inherit this context through their project/phase association; do not duplicate registration identifiers on each unit. Keep unmatched and pending-review registrations available for reconciliation, and represent unknown or absent status explicitly rather than inferring legal conclusions.

### Use curated reads for portal and analytics consumers

Expose database views or equivalent read models for property profile, document timeline, current listings, project/RERA context, and aggregate trends. Analytics reads include source coverage and classification context. Future WhatsApp access should use approved views or a constrained query interface rather than direct arbitrary SQL over raw source or sensitive CRM tables.

### Preserve CRM controls with Supabase RLS and history

Keep leads, contacts, mobile captures, follow-ups, users, roles, permissions, and assignments separate from source evidence and listings. User-facing access uses Supabase Auth identity plus indexed role/assignment policies. Raw source payloads and sensitive CRM fields remain restricted. Current workflow state is queryable on its entity; append-only transition/audit records retain actor, timestamp, prior/new state, and reason when applicable.

### Separate sourced contacts, owner matches, intent, and listings

Store external phone-number provenance on contact-method source evidence. Link a contact method to a property and optionally to a registration-document party through a property-scoped match record with candidate/confirmed/rejected state, method, evidence, confidence, and reviewer. This supports calling an unverified candidate without claiming that the number belongs to the legal owner.

Represent each property's sale and rent qualification as separate owner-intent records tied to a property-contact match. Keep the workflow status (queued, reached, callback, interested, not interested, and similar outcomes) separate from the intent type (`sale` or `rent`). Append each call attempt with actor, time, outcome, and note, and record intent status transitions separately. Do not automatically create a listing from a call or intent; create/update a sale or rent listing only after offer details are confirmed. Retain the existing generic lead table for compatibility, but use owner-intent tracks for the new MVP calling workflow.

### Use additive migrations and a staged backfill

Create shared reference data and geographic/source identity foundations first, then canonical development/property entities, source observations, registry documents/schedules/parties, RERA and listings, CRM workflows, access controls, indexes, and curated reads. Load historical SRO records into staging, validate source identities and parsing, produce duplicate/match reports, review uncertain links, then promote accepted matches. Daily ingestion reuses the same staging and reconciliation path. Apply migrations to a clean database and retain rollback checkpoints; do not delete source or audit history during rollback.

## Risks / Trade-offs

- **[Risk]** Survey identifiers and project names may be ambiguous or reused. **Mitigation:** scope identifiers geographically, preserve raw values and aliases, and require review for low-confidence matches.
- **[Risk]** Historical and daily imports may overlap or contain source corrections. **Mitigation:** use source-scoped document identity, import-run provenance, immutable observations, and replayable parsing.
- **[Risk]** SRO consideration can be misread as a sale price. **Mitigation:** preserve recorded values verbatim and expose analytics only through explicit document classification rules.
- **[Risk]** RERA records may not map uniquely to a development or phase. **Mitigation:** retain unmatched records and match confidence/review state; never infer status from absence.
- **[Risk]** Complex assignment RLS may be slow or recursive. **Mitigation:** index assignment paths, centralize policy-safe membership checks, and test role queries.
- **[Risk]** Raw records can contain inconsistent or sensitive text. **Mitigation:** restrict raw payload access, validate normalized fields before promotion, and define retention rules.
- **[Risk]** External phone numbers may be stale, shared, or incorrectly attributed. **Mitigation:** retain source evidence and match review state, and do not mark a candidate as an owner contact until verified.

## Migration Plan

1. Apply the database foundation, reference values, geographic context, and source identity tables; verify a clean database migration.
2. Add canonical projects, phases, property types, survey identifiers, source observations, document/schedule/party relationships, RERA, listings, CRM, and audit structures with constraints and indexes.
3. Apply RLS and curated read models; verify policies with representative admin, telecaller, sales, and third-party identities.
4. Backfill SRO history from 2010 onward into staging, validate document identities and parser outputs, review duplicate and ambiguous property/RERA matches, then promote accepted links.
5. Enable daily SRO ingestion through the same idempotent staging and reconciliation path; verify replay and source-correction handling.
6. Roll back by disabling writes and restoring the last migration checkpoint; retain source observations and audit history.
7. Add sourced contact evidence, reviewed property/party-to-contact matches, independent sale/rent intent tracks, call attempts, status history, and assignment-based policies as an additive CRM migration.
