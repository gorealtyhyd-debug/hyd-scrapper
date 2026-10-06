# Proposal

## Why

The initial product supports resale and rental workflows for apartments, villas, and open plots in Hyderabad, while collected SRO data covers a broader range of properties and legal documents. A normalized database is needed to preserve historical registrations from 2010 onward, ingest new SRO records daily, connect RERA registrations to developments, and keep legal history distinct from current listings and CRM workflows.

## What Changes

- Define a normalized Supabase/PostgreSQL model for canonical properties, development projects and phases, locations, survey identifiers, listings, source observations, registration documents and schedules, parties, RERA registrations, and CRM workflows.
- Support apartments, villas, and open plots as initial customer-facing categories while allowing additional property types and preserving all property types found in source data.
- Separate sale and rental listings from canonical properties and SRO registration events; allow multiple listing records over a property's lifetime.
- Preserve all received SRO document types and link documents, schedules, parties, and canonical properties without assuming one document equals one property or that a claimant is necessarily an owner.
- Define source identity and idempotent reconciliation for the 2010 historical backfill and daily SRO ingestion. Retain raw source data, fetch and observation timestamps, parser versions, and corrections.
- Link RERA registrations to developments or phases and their properties while preserving source, status history, dates, and match review state.
- Provide curated property-history and analytics reads that distinguish classified sale events from other registrations and report source coverage.
- Retain relational integrity, auditability, CRM lifecycle requirements, and role- and assignment-based access controls.
- Support the initial calling workflow with sourced contact-number evidence, reviewed property/party-to-contact matches, independent resale and rental intent tracks, and call-attempt history.

## Capabilities

### New Capabilities

- `property-crm-data-model`: Canonical property, listing, source-history, registration, RERA, CRM, access-control, and analytics-read contracts.

### Modified Capabilities

None. The repository has no durable main capability specs yet; this change introduces the initial property CRM data-model capability.

## Impact

- Establishes the Supabase/PostgreSQL contract for the property portal, CRM, historical SRO backfill, and daily SRO updates.
- Requires schema migrations, source identity and matching rules, import validation, indexes, constraints, RLS policies, and data-model tests.
- Enables future WhatsApp analytics through curated reads; implementing the WhatsApp bot and customer-facing screens is outside this change.
- SRO records are not a complete source of current resale or rental availability, and missing RERA data does not establish legal status.
- Contact numbers from external sources remain candidates until reviewed; confirmed owner intent is distinct from a property listing, which is created only when an offer is verified.