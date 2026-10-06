CREATE TABLE public.rera_project_matches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  rera_registration_id uuid NOT NULL REFERENCES public.rera_registrations(id) ON DELETE RESTRICT,
  development_project_id uuid NOT NULL REFERENCES public.development_projects(id) ON DELETE RESTRICT,
  development_phase_id uuid,
  match_method text NOT NULL CHECK (match_method IN (
    'project_identifier', 'name_location', 'survey_number', 'manual_review'
  )),
  match_status text NOT NULL DEFAULT 'pending' CHECK (match_status IN ('pending', 'accepted', 'rejected')),
  confidence numeric(5, 4) CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1),
  source_reference text NOT NULL,
  reviewed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (development_phase_id, development_project_id)
    REFERENCES public.development_phases (id, development_project_id)
    ON DELETE RESTRICT,
  CHECK (length(btrim(source_reference)) > 0),
  UNIQUE NULLS NOT DISTINCT (
    rera_registration_id,
    development_project_id,
    development_phase_id,
    source_reference
  )
);

CREATE UNIQUE INDEX rera_one_accepted_match_idx
  ON public.rera_project_matches (rera_registration_id)
  WHERE match_status = 'accepted';

CREATE INDEX rera_project_matches_review_idx
  ON public.rera_project_matches (match_status, confidence);

CREATE VIEW public.property_rera_registrations
WITH (security_invoker = true)
AS
SELECT
  property.id AS property_id,
  registration.id AS rera_registration_id,
  registration.registration_number_raw,
  match.development_project_id,
  match.development_phase_id,
  observation.project_name_as_recorded,
  observation.promoter_name_as_recorded,
  observation.status_as_recorded,
  observation.registered_on,
  observation.valid_until,
  observation.observed_at
FROM public.properties AS property
JOIN public.rera_project_matches AS match
  ON match.development_project_id = property.development_project_id
 AND (match.development_phase_id IS NULL OR match.development_phase_id = property.development_phase_id)
 AND match.match_status = 'accepted'
JOIN public.rera_registrations AS registration
  ON registration.id = match.rera_registration_id
LEFT JOIN LATERAL (
  SELECT rera_observation.*
  FROM public.rera_registration_observations AS rera_observation
  WHERE rera_observation.rera_registration_id = registration.id
  ORDER BY rera_observation.observed_at DESC, rera_observation.id DESC
  LIMIT 1
) AS observation ON true;