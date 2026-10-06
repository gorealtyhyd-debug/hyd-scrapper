CREATE TABLE public.import_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_system_code text NOT NULL REFERENCES public.source_systems(code) ON DELETE RESTRICT,
  registration_office_id uuid REFERENCES public.registration_offices(id) ON DELETE RESTRICT,
  run_kind text NOT NULL CHECK (run_kind IN ('historical_backfill', 'daily', 'replay', 'manual')),
  run_status text NOT NULL DEFAULT 'running' CHECK (run_status IN ('running', 'completed', 'completed_with_errors', 'failed')),
  requested_from date,
  requested_to date,
  started_at timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz,
  record_count integer NOT NULL DEFAULT 0 CHECK (record_count >= 0),
  error_count integer NOT NULL DEFAULT 0 CHECK (error_count >= 0),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(metadata) = 'object'),
  CHECK (requested_to IS NULL OR requested_from IS NULL OR requested_to >= requested_from),
  CHECK (finished_at IS NULL OR finished_at >= started_at)
);

CREATE TABLE public.source_observations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_system_code text NOT NULL REFERENCES public.source_systems(code) ON DELETE RESTRICT,
  registration_office_id uuid REFERENCES public.registration_offices(id) ON DELETE RESTRICT,
  source_record_type text NOT NULL,
  source_record_key text NOT NULL,
  content_hash text NOT NULL CHECK (content_hash ~ '^[a-f0-9]{64}$'),
  raw_payload jsonb NOT NULL CHECK (jsonb_typeof(raw_payload) = 'object'),
  parsed_payload jsonb CHECK (parsed_payload IS NULL OR jsonb_typeof(parsed_payload) = 'object'),
  parser_version text NOT NULL,
  source_observed_at timestamptz,
  parse_status text NOT NULL DEFAULT 'pending' CHECK (parse_status IN ('pending', 'parsed', 'invalid', 'promoted')),
  validation_errors jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(validation_errors) = 'array'),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE NULLS NOT DISTINCT (
    source_system_code,
    registration_office_id,
    source_record_type,
    source_record_key,
    content_hash
  ),
  CHECK (length(btrim(source_record_key)) > 0),
  CHECK (length(btrim(parser_version)) > 0)
);

CREATE TABLE public.source_observation_sightings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_observation_id uuid NOT NULL REFERENCES public.source_observations(id) ON DELETE RESTRICT,
  import_run_id uuid NOT NULL REFERENCES public.import_runs(id) ON DELETE RESTRICT,
  fetched_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  response_metadata jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(response_metadata) = 'object'),
  UNIQUE (source_observation_id, import_run_id)
);

CREATE INDEX source_observations_key_idx
  ON public.source_observations (source_system_code, registration_office_id, source_record_type, source_record_key);

CREATE INDEX source_observations_status_idx
  ON public.source_observations (parse_status, created_at);

CREATE INDEX import_runs_source_time_idx
  ON public.import_runs (source_system_code, started_at DESC);

CREATE INDEX source_observation_sightings_run_idx
  ON public.source_observation_sightings (import_run_id, fetched_at);