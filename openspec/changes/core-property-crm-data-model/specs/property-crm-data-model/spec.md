# Spec Delta

## Purpose

Defines the relational contract for extensible property inventory, active resale and rental listings, source-backed SRO and RERA history, and CRM workflows.

## ADDED Requirements

### Requirement: The system SHALL maintain canonical properties across supported and future property types

The data model SHALL represent a canonical property independently from its source observations and customer-facing listings. It SHALL support apartments, villas, and open plots for initial resale and rental workflows, and SHALL preserve other property types encountered in source data without requiring a redesign. Properties SHALL be linkable to geographic context, development projects or phases, and applicable survey identifiers. A property identity SHALL use stable internal identifiers and scoped business/source identifiers rather than relying only on a mutable display name.

#### Scenario: Property types outside the initial product scope are ingested
- **WHEN** a source observation describes a property type not enabled for initial resale or rental workflows
- **THEN** the system preserves the observation and can link it to a canonical property without presenting it as an active supported listing

#### Scenario: Similar property labels resolve to one reviewed identity
- **WHEN** source records use different names for the same project, phase, block, or unit
- **THEN** the system can retain each source label and associate observations with one canonical property through a recorded match or review decision

### Requirement: The system SHALL preserve source observations and support repeatable historical and daily SRO ingestion

The system SHALL retain source identity, raw payload or source values, observed and fetched timestamps, parser version, and import-run provenance for ingested records. Historical records from 2010 onward and daily registrations from each configured SRO SHALL be idempotently reconciled using source-scoped identifiers. Repeated retrieval SHALL NOT create duplicate source documents or observations for the same source version, and corrections or later observations SHALL remain traceable.

#### Scenario: Historical backfill is replayed
- **WHEN** the same historical SRO range is imported more than once
- **THEN** the system retains one source document identity, avoids duplicate canonical records, and records distinct retrievals or source versions as provenance

#### Scenario: A daily SRO registration is received
- **WHEN** a configured SRO publishes a new registration after the historical backfill
- **THEN** the system stores it under the same source identity rules and makes it available for property matching without overwriting prior evidence

#### Scenario: A source record is corrected
- **WHEN** a later SRO observation differs from a previously stored source record
- **THEN** the system retains the prior observation and records the newer values and observation time

### Requirement: The system SHALL model registration documents, schedules, parties, and property links separately

The data model SHALL preserve all received SRO document types and distinguish a registration document from its one or more schedules and their property references. A document SHALL be uniquely identified within its source context using the SRO and available registration-year, book, and document identifiers. Schedules SHALL link to zero or more canonical properties, and a canonical property SHALL link to multiple schedules and documents over time. Party relationships SHALL preserve source-recorded role codes without treating a role as a definitive ownership conclusion.

#### Scenario: One document references multiple schedules or properties
- **WHEN** an SRO document contains multiple schedules or a schedule describes multiple properties
- **THEN** the system stores the document once and preserves each schedule-to-property relationship independently

#### Scenario: A property appears in multiple registration documents
- **WHEN** multiple SRO documents reference the same canonical property
- **THEN** the system links each document schedule to that property and exposes the linked documents as its registration history

#### Scenario: A document contains multiple parties
- **WHEN** a registration document lists multiple parties with recorded role codes
- **THEN** the system stores each party-document relationship and its original role without automatically asserting current ownership

### Requirement: The system SHALL preserve survey identifiers in geographic context

Survey numbers and subdivisions SHALL be stored with the applicable SRO and administrative/geographic context and their original source representation. The model SHALL support aliases and recorded relationships between identifiers so that reuse, formatting differences, or renumbering do not silently merge distinct parcels or erase historical references.

#### Scenario: A survey number repeats in another geographic context
- **WHEN** the same survey number is received for different village or SRO contexts
- **THEN** the system stores distinct scoped identifiers rather than treating them as the same parcel

#### Scenario: A survey identifier has an alias or historical relationship
- **WHEN** source evidence identifies a formatting alias, subdivision, or successor identifier
- **THEN** the system preserves both identifiers and the relationship with its source evidence

### Requirement: The system SHALL distinguish active resale and rental listings from property and legal history

Listings SHALL be separate records linked to canonical properties and SHALL identify sale or rental intent, price and currency or period where available, availability, source, and lifecycle status. A property SHALL support multiple listings over time. SRO registrations SHALL NOT by themselves create or imply an active listing or current availability.

#### Scenario: A property is listed for resale and later for rent
- **WHEN** separate resale and rental offers are recorded for the same property at different times
- **THEN** the system stores distinct listing records and preserves each listing's type, dates, source, and lifecycle state

#### Scenario: An SRO document is ingested for an unlisted property
- **WHEN** a registration document is linked to a property with no active listing
- **THEN** the system adds to the property's legal history without creating an active resale or rental offer

### Requirement: The system SHALL link RERA registrations to developments and phases

The data model SHALL represent RERA registrations as sourced records linked to the applicable development project or phase, with properties related through their project or phase relationship. RERA identifiers SHALL remain distinct from SRO document identifiers. Registration status, relevant dates, source provenance, observations over time, and match or review state SHALL be retained. Missing RERA data SHALL NOT be interpreted as proof of registration, exemption, or non-compliance.

#### Scenario: A development phase has a RERA registration
- **WHEN** a RERA record is matched to a development phase
- **THEN** the system links the registration to that phase and makes it available to properties associated with that phase

#### Scenario: A RERA match is uncertain
- **WHEN** project name, promoter, location, or survey references do not establish a reliable match
- **THEN** the system retains the RERA source record as unmatched or pending review rather than silently linking it

### Requirement: The system SHALL provide source-aware property history and analytics reads

The system SHALL expose query-ready reads that combine canonical properties with linked schedules, registration documents, source classifications, and applicable RERA and listing information. Analytics SHALL distinguish document types and recorded market value and consideration from a classified sale event and SHALL make source coverage available to consumers. A sale trend SHALL include only records classified as qualifying sale events under explicit classification rules.

#### Scenario: Property history is requested
- **WHEN** an authorized consumer requests a property's history
- **THEN** the result includes its linked registration documents and schedules in registration-date order with source identity and document type

#### Scenario: Sale analytics exclude non-sale documents
- **WHEN** a consumer requests a sale-price trend
- **THEN** the result excludes mortgages, releases, rectifications, and other non-sale document types and reports the applied coverage or classification context

### Requirement: The system SHALL support CRM lifecycle, role-based access, and auditability

The data model SHALL support contacts, mobile captures, leads, qualification statuses, follow-ups, users, roles, permissions, and project/property assignments. Access policies SHALL enforce role and assignment scope for sensitive CRM and source data. Foreign keys, uniqueness and status constraints, timestamps, and audit history SHALL prevent orphaned records and preserve significant identity, source, listing, workflow, and permission changes.

#### Scenario: A lead status changes
- **WHEN** an authorized user changes a lead's qualification status
- **THEN** the system records the current status and an auditable transition with actor and timestamp

#### Scenario: A user requests an unassigned property record
- **WHEN** a role-restricted user requests a record outside the user's assignment
- **THEN** the database denies access rather than relying only on a user-interface filter

#### Scenario: A sensitive record is changed
- **WHEN** a source-to-property match, assignment, listing lifecycle state, or permission-sensitive CRM value changes
- **THEN** the system records the actor, event time, affected entity, and relevant change information

### Requirement: The system SHALL preserve provenance and review state for sourced owner contact numbers

The system SHALL retain the source and collection time for contact methods obtained from external sources. A contact method SHALL be linkable to a property and, when evidence permits, to a legal party recorded for that property. Candidate, confirmed, and rejected matches SHALL remain distinguishable; an unreviewed phone number SHALL NOT be represented as a confirmed owner's number.

#### Scenario: A phone number is imported from an external source
- **WHEN** an authorized user adds a phone number found in an external source
- **THEN** the system stores the number, source reference, collection time, and a candidate match to the relevant property/contact without asserting owner identity

#### Scenario: A candidate contact is confirmed as a property party
- **WHEN** an authorized user verifies that a contact belongs to a recorded party associated with a property
- **THEN** the system records a confirmed property/contact/party match with reviewer, time, and evidence while retaining prior source provenance

### Requirement: The system SHALL track resale and rental intent independently for each property contact

The system SHALL represent sale intent and rental intent as separate qualification tracks associated with a property and its matched contact. Each track SHALL have its own outreach status, qualification history, expected amount when known, and call attempts with actor, time, outcome, and notes. Call outcomes and workflow status SHALL NOT be conflated with intent type. A property SHALL NOT become an active listing solely because an owner was contacted or expressed an unqualified intent.

#### Scenario: The same owner considers both resale and rental
- **WHEN** a property contact expresses resale intent and rental intent at different times or in parallel
- **THEN** the system stores independent sale and rent intent records whose status, expected amount, and history can change separately

#### Scenario: A call attempt has no answer
- **WHEN** a telecaller records an unanswered call for an intent track
- **THEN** the system appends a call attempt with actor, time, and no-answer outcome without changing the other intent track

#### Scenario: An owner confirms an offer
- **WHEN** an owner confirms sale or rental availability and the offer details are verified
- **THEN** an authorized user can create or update the corresponding sale or rental listing separately from the intent and call history