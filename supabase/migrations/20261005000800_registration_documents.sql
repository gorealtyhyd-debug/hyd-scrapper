CREATE TABLE public.registration_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_system_code text NOT NULL REFERENCES public.source_systems(code) ON DELETE RESTRICT,
  registration_office_id uuid NOT NULL REFERENCES public.registration_offices(id) ON DELETE RESTRICT,
  registration_year integer NOT NULL CHECK (registration_year BETWEEN 1900 AND 2200),
  book_no text NOT NULL DEFAULT '',
  document_no text NOT NULL,
  document_type_code text REFERENCES public.document_types(code) ON DELETE RESTRICT,
  document_type_as_recorded text NOT NULL DEFAULT '',
  execution_date date,
  registration_date date,
  presentation_date date,
  market_value numeric(16, 2) CHECK (market_value IS NULL OR market_value >= 0),
  consideration_value numeric(16, 2) CHECK (consideration_value IS NULL OR consideration_value >= 0),
  volume_no text,
  cd_no text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (source_system_code, registration_office_id, registration_year, book_no, document_no),
  CHECK (length(btrim(document_no)) > 0)
);

CREATE TABLE public.registration_document_observations (
  registration_document_id uuid NOT NULL REFERENCES public.registration_documents(id) ON DELETE RESTRICT,
  source_observation_id uuid NOT NULL REFERENCES public.source_observations(id) ON DELETE RESTRICT,
  linked_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (registration_document_id, source_observation_id)
);

CREATE TABLE public.registration_schedules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  registration_document_id uuid NOT NULL REFERENCES public.registration_documents(id) ON DELETE RESTRICT,
  schedule_number text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (registration_document_id, schedule_number),
  CHECK (length(btrim(schedule_number)) > 0)
);

CREATE TABLE public.registration_schedule_observations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  registration_schedule_id uuid NOT NULL REFERENCES public.registration_schedules(id) ON DELETE RESTRICT,
  source_observation_id uuid NOT NULL REFERENCES public.source_observations(id) ON DELETE RESTRICT,
  raw_property_description text NOT NULL DEFAULT '',
  parsed_property_details jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(parsed_property_details) = 'object'),
  observed_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (registration_schedule_id, source_observation_id)
);

CREATE INDEX registration_documents_property_history_idx
  ON public.registration_documents (registration_office_id, registration_date DESC, document_no);

CREATE INDEX registration_schedules_document_idx
  ON public.registration_schedules (registration_document_id, schedule_number);

CREATE INDEX registration_schedule_observations_source_idx
  ON public.registration_schedule_observations (source_observation_id);

CREATE TRIGGER registration_documents_updated_at
  BEFORE UPDATE ON public.registration_documents
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();