CREATE TABLE public.geographic_areas (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  area_type text NOT NULL CHECK (area_type IN ('state', 'district', 'mandal', 'village', 'locality')),
  parent_id uuid REFERENCES public.geographic_areas(id) ON DELETE RESTRICT,
  source_system_code text REFERENCES public.source_systems(code) ON DELETE RESTRICT,
  external_code text,
  source_name text NOT NULL,
  normalized_name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE NULLS NOT DISTINCT (parent_id, area_type, normalized_name)
);

CREATE TABLE public.geographic_area_aliases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  geographic_area_id uuid NOT NULL REFERENCES public.geographic_areas(id) ON DELETE CASCADE,
  source_system_code text REFERENCES public.source_systems(code) ON DELETE RESTRICT,
  raw_name text NOT NULL,
  source_reference text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE NULLS NOT DISTINCT (geographic_area_id, source_system_code, raw_name)
);

CREATE TABLE public.registration_offices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_system_code text NOT NULL REFERENCES public.source_systems(code) ON DELETE RESTRICT,
  sro_code text NOT NULL,
  name text NOT NULL,
  geographic_area_id uuid REFERENCES public.geographic_areas(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (source_system_code, sro_code)
);

CREATE TABLE public.survey_identifiers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  registration_office_id uuid NOT NULL REFERENCES public.registration_offices(id) ON DELETE RESTRICT,
  village_area_id uuid NOT NULL REFERENCES public.geographic_areas(id) ON DELETE RESTRICT,
  raw_identifier text NOT NULL,
  normalized_identifier text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (registration_office_id, village_area_id, normalized_identifier),
  CHECK (length(btrim(raw_identifier)) > 0),
  CHECK (length(btrim(normalized_identifier)) > 0)
);

CREATE OR REPLACE FUNCTION public.require_village_area()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  referenced_area_type text;
BEGIN
  SELECT area_type
  INTO referenced_area_type
  FROM public.geographic_areas
  WHERE id = NEW.village_area_id;

  IF referenced_area_type IS DISTINCT FROM 'village' THEN
    RAISE EXCEPTION 'survey identifiers must reference a village area';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER survey_identifiers_require_village
  BEFORE INSERT OR UPDATE OF village_area_id ON public.survey_identifiers
  FOR EACH ROW EXECUTE FUNCTION public.require_village_area();

CREATE TABLE public.survey_identifier_aliases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  survey_identifier_id uuid NOT NULL REFERENCES public.survey_identifiers(id) ON DELETE CASCADE,
  raw_alias text NOT NULL,
  normalized_alias text NOT NULL,
  source_system_code text REFERENCES public.source_systems(code) ON DELETE RESTRICT,
  source_reference text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (survey_identifier_id, normalized_alias),
  CHECK (length(btrim(raw_alias)) > 0),
  CHECK (length(btrim(normalized_alias)) > 0)
);

CREATE TABLE public.survey_identifier_relations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  from_survey_identifier_id uuid NOT NULL REFERENCES public.survey_identifiers(id) ON DELETE RESTRICT,
  to_survey_identifier_id uuid NOT NULL REFERENCES public.survey_identifiers(id) ON DELETE RESTRICT,
  relation_type text NOT NULL CHECK (relation_type IN ('subdivision', 'successor', 'renumbered_to')),
  source_reference text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (from_survey_identifier_id, to_survey_identifier_id, relation_type),
  CHECK (from_survey_identifier_id <> to_survey_identifier_id)
);

CREATE INDEX survey_identifiers_village_idx
  ON public.survey_identifiers (village_area_id, normalized_identifier);

CREATE INDEX geographic_areas_parent_idx
  ON public.geographic_areas (parent_id, area_type);