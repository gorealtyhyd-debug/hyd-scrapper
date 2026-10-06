CREATE TABLE public.registration_document_relations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  from_registration_document_id uuid NOT NULL REFERENCES public.registration_documents(id) ON DELETE RESTRICT,
  to_registration_document_id uuid NOT NULL REFERENCES public.registration_documents(id) ON DELETE RESTRICT,
  relation_type text NOT NULL CHECK (relation_type IN (
    'rectifies', 'cancels', 'releases', 'supplements', 'supersedes', 'references', 'other'
  )),
  source_reference text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (from_registration_document_id, to_registration_document_id, relation_type),
  CHECK (from_registration_document_id <> to_registration_document_id)
);

CREATE INDEX registration_document_relations_target_idx
  ON public.registration_document_relations (to_registration_document_id, relation_type);

CREATE VIEW public.property_registration_history
WITH (security_invoker = true)
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
WHERE match.match_status = 'accepted';

CREATE VIEW public.property_sale_events
WITH (security_invoker = true)
AS
SELECT *
FROM public.property_registration_history
WHERE is_sale_event IS TRUE;