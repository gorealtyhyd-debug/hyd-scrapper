CREATE TABLE public.rera_registrations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_system_code text NOT NULL REFERENCES public.source_systems(code) ON DELETE RESTRICT,
  registration_number_raw text NOT NULL,
  normalized_registration_number text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (source_system_code, normalized_registration_number),
  CHECK (length(btrim(registration_number_raw)) > 0),
  CHECK (length(btrim(normalized_registration_number)) > 0)
);

CREATE TABLE public.rera_registration_observations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  observation_sequence bigint GENERATED ALWAYS AS IDENTITY UNIQUE,
  rera_registration_id uuid NOT NULL REFERENCES public.rera_registrations(id) ON DELETE RESTRICT,
  source_observation_id uuid NOT NULL REFERENCES public.source_observations(id) ON DELETE RESTRICT,
  project_name_as_recorded text,
  promoter_name_as_recorded text,
  status_as_recorded text,
  registered_on date,
  valid_until date,
  source_url text,
  observed_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (rera_registration_id, source_observation_id),
  CHECK (valid_until IS NULL OR registered_on IS NULL OR valid_until >= registered_on)
);

CREATE INDEX rera_registration_observations_timeline_idx
  ON public.rera_registration_observations (rera_registration_id, observed_at DESC);

CREATE INDEX rera_registration_observations_status_idx
  ON public.rera_registration_observations (status_as_recorded, valid_until);