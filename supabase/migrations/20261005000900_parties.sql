CREATE TABLE public.parties (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  party_type text NOT NULL DEFAULT 'unknown' CHECK (party_type IN ('person', 'organization', 'unknown')),
  canonical_name text NOT NULL,
  normalized_name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (length(btrim(canonical_name)) > 0),
  CHECK (length(btrim(normalized_name)) > 0)
);

CREATE TABLE public.party_aliases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  party_id uuid NOT NULL REFERENCES public.parties(id) ON DELETE RESTRICT,
  source_system_code text REFERENCES public.source_systems(code) ON DELETE RESTRICT,
  raw_name text NOT NULL,
  normalized_name text NOT NULL,
  source_reference text,
  match_status text NOT NULL DEFAULT 'pending' CHECK (match_status IN ('pending', 'accepted', 'rejected')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE NULLS NOT DISTINCT (party_id, source_system_code, normalized_name, source_reference)
);

CREATE TABLE public.registration_document_parties (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  registration_document_id uuid NOT NULL REFERENCES public.registration_documents(id) ON DELETE RESTRICT,
  source_observation_id uuid REFERENCES public.source_observations(id) ON DELETE RESTRICT,
  party_id uuid REFERENCES public.parties(id) ON DELETE RESTRICT,
  party_role_code text NOT NULL REFERENCES public.party_roles(code) ON DELETE RESTRICT,
  source_role_code text NOT NULL,
  source_party_sequence integer CHECK (source_party_sequence IS NULL OR source_party_sequence > 0),
  source_name_as_recorded text NOT NULL,
  representative_as_recorded text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE NULLS NOT DISTINCT (registration_document_id, source_observation_id, source_party_sequence),
  CHECK (length(btrim(source_role_code)) > 0),
  CHECK (length(btrim(source_name_as_recorded)) > 0)
);

CREATE INDEX registration_document_parties_party_idx
  ON public.registration_document_parties (party_id, registration_document_id);

CREATE INDEX registration_document_parties_role_idx
  ON public.registration_document_parties (party_role_code, registration_document_id);

CREATE TRIGGER parties_updated_at
  BEFORE UPDATE ON public.parties
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();