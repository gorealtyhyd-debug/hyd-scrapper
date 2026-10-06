DROP VIEW public.property_sale_events;
DROP VIEW public.property_registration_history;

CREATE VIEW public.property_registration_history
WITH (security_barrier = true)
AS
SELECT
  match.property_id,
  document.id AS registration_document_id,
  document.source_system_code,
  office.sro_code,
  document.registration_year,
  document.book_no,
  document.document_no,
  document.document_type_code,
  document.document_type_as_recorded,
  document.registration_date,
  document.execution_date,
  document.presentation_date,
  document.market_value,
  document.consideration_value,
  schedule.schedule_number,
  schedule_observation.id AS schedule_observation_id,
  schedule_observation.source_observation_id,
  document_type.is_sale_event
FROM public.registration_schedule_property_matches AS match
JOIN public.registration_schedule_observations AS schedule_observation
  ON schedule_observation.id = match.registration_schedule_observation_id
JOIN public.registration_schedules AS schedule
  ON schedule.id = schedule_observation.registration_schedule_id
JOIN public.registration_documents AS document
  ON document.id = schedule.registration_document_id
JOIN public.registration_offices AS office
  ON office.id = document.registration_office_id
LEFT JOIN public.document_types AS document_type
  ON document_type.code = document.document_type_code
WHERE match.match_status = 'accepted'
  AND public.current_user_has_permission('inventory.read')
  AND NOT public.current_user_has_role('third_party')
  AND (
    public.current_user_has_role('admin')
    OR public.current_user_has_property_assignment(match.property_id)
  );

CREATE VIEW public.property_sale_events
WITH (security_barrier = true)
AS
SELECT *
FROM public.property_registration_history
WHERE is_sale_event IS TRUE;

CREATE VIEW public.property_profile_read
WITH (security_barrier = true)
AS
SELECT
  property.id AS property_id,
  property.property_type_code,
  property_type.label AS property_type_label,
  property.display_name,
  property.geographic_area_id,
  area.source_name AS geographic_area_name,
  property.development_project_id,
  project.display_name AS development_project_name,
  property.development_phase_id,
  phase.display_name AS development_phase_name,
  property.parent_property_id
FROM public.properties AS property
JOIN public.property_types AS property_type ON property_type.code = property.property_type_code
LEFT JOIN public.geographic_areas AS area ON area.id = property.geographic_area_id
LEFT JOIN public.development_projects AS project ON project.id = property.development_project_id
LEFT JOIN public.development_phases AS phase ON phase.id = property.development_phase_id
WHERE public.current_user_has_permission('inventory.read')
  AND NOT public.current_user_has_role('third_party')
  AND (
    public.current_user_has_role('admin')
    OR public.current_user_has_property_assignment(property.id)
  );

CREATE VIEW public.property_current_listings
WITH (security_barrier = true)
AS
SELECT
  listing.id AS listing_id,
  listing.property_id,
  listing.listing_type_code,
  listing.asking_price,
  listing.currency_code,
  listing.rent_period,
  listing.available_from,
  listing.published_at,
  listing.source_system_code
FROM public.property_listings AS listing
WHERE listing.listing_status_code = 'active'
  AND (listing.ended_at IS NULL OR listing.ended_at >= CURRENT_DATE)
  AND public.current_user_has_permission('listing.read')
  AND (
    public.current_user_has_role('admin')
    OR (NOT public.current_user_has_role('third_party')
        AND public.current_user_has_property_assignment(listing.property_id))
  );

CREATE VIEW public.property_sale_trends_monthly
WITH (security_barrier = true)
AS
SELECT
  date_trunc('month', event.registration_date)::date AS registration_month,
  property.geographic_area_id,
  property.property_type_code,
  count(DISTINCT event.registration_document_id)::integer AS sale_event_count,
  count(event.consideration_value)::integer AS consideration_value_count,
  avg(event.consideration_value) AS average_recorded_consideration,
  avg(event.market_value) AS average_recorded_market_value,
  count(DISTINCT event.sro_code)::integer AS source_sro_count,
  array_agg(DISTINCT event.document_type_code ORDER BY event.document_type_code) AS included_document_type_codes
FROM public.property_sale_events AS event
JOIN public.properties AS property ON property.id = event.property_id
WHERE event.registration_date IS NOT NULL
  AND public.current_user_has_role('admin')
  AND public.current_user_has_permission('analytics.read')
GROUP BY
  date_trunc('month', event.registration_date)::date,
  property.geographic_area_id,
  property.property_type_code;

CREATE VIEW public.source_coverage_by_sro
WITH (security_barrier = true)
AS
SELECT
  office.source_system_code,
  office.sro_code,
  office.name AS sro_name,
  count(DISTINCT observation.id)::integer AS source_observation_count,
  count(DISTINCT observation.id) FILTER (WHERE observation.parse_status = 'promoted')::integer AS promoted_observation_count,
  count(DISTINCT observation.id) FILTER (WHERE observation.parse_status = 'invalid')::integer AS invalid_observation_count,
  count(DISTINCT document.id)::integer AS registration_document_count,
  min(NULLIF(observation.parsed_payload ->> 'registration_date', '')::date) AS first_registration_date,
  max(NULLIF(observation.parsed_payload ->> 'registration_date', '')::date) AS last_registration_date,
  max(sighting.fetched_at) AS last_fetched_at
FROM public.registration_offices AS office
LEFT JOIN public.source_observations AS observation
  ON observation.registration_office_id = office.id
LEFT JOIN public.source_observation_sightings AS sighting
  ON sighting.source_observation_id = observation.id
LEFT JOIN public.registration_document_observations AS document_observation
  ON document_observation.source_observation_id = observation.id
LEFT JOIN public.registration_documents AS document
  ON document.id = document_observation.registration_document_id
WHERE office.source_system_code = 'telangana_sro'
  AND public.current_user_has_role('admin')
  AND public.current_user_has_permission('analytics.read')
GROUP BY office.source_system_code, office.sro_code, office.name;

GRANT SELECT ON
  public.property_registration_history,
  public.property_sale_events,
  public.property_profile_read,
  public.property_current_listings,
  public.property_sale_trends_monthly,
  public.source_coverage_by_sro
TO authenticated;