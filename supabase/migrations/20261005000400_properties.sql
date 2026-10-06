CREATE TABLE public.development_projects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_type text NOT NULL CHECK (project_type IN (
    'apartment_community', 'villa_community', 'plotted_development', 'mixed_use', 'other'
  )),
  display_name text NOT NULL,
  normalized_name text NOT NULL,
  geographic_area_id uuid REFERENCES public.geographic_areas(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE NULLS NOT DISTINCT (normalized_name, geographic_area_id)
);

CREATE TABLE public.development_project_aliases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  development_project_id uuid NOT NULL REFERENCES public.development_projects(id) ON DELETE CASCADE,
  source_system_code text REFERENCES public.source_systems(code) ON DELETE RESTRICT,
  raw_name text NOT NULL,
  normalized_name text NOT NULL,
  source_reference text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE NULLS NOT DISTINCT (development_project_id, source_system_code, normalized_name)
);

CREATE TABLE public.development_phases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  development_project_id uuid NOT NULL REFERENCES public.development_projects(id) ON DELETE RESTRICT,
  display_name text NOT NULL,
  normalized_name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (id, development_project_id),
  UNIQUE (development_project_id, normalized_name)
);

CREATE TABLE public.properties (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_type_code text NOT NULL REFERENCES public.property_types(code) ON DELETE RESTRICT,
  display_name text NOT NULL,
  normalized_name text NOT NULL,
  geographic_area_id uuid REFERENCES public.geographic_areas(id) ON DELETE RESTRICT,
  development_project_id uuid REFERENCES public.development_projects(id) ON DELETE RESTRICT,
  development_phase_id uuid,
  parent_property_id uuid REFERENCES public.properties(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (development_phase_id, development_project_id)
    REFERENCES public.development_phases (id, development_project_id)
    ON DELETE RESTRICT,
  CHECK (development_phase_id IS NULL OR development_project_id IS NOT NULL),
  CHECK (parent_property_id IS NULL OR parent_property_id <> id)
);

CREATE TABLE public.property_aliases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id uuid NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
  source_system_code text REFERENCES public.source_systems(code) ON DELETE RESTRICT,
  raw_name text NOT NULL,
  normalized_name text NOT NULL,
  source_reference text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE NULLS NOT DISTINCT (property_id, source_system_code, normalized_name)
);

CREATE TABLE public.property_identifiers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id uuid NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
  identifier_type text NOT NULL CHECK (identifier_type IN (
    'flat_number', 'unit_number', 'plot_number', 'house_number', 'source_property_id', 'other'
  )),
  raw_value text NOT NULL,
  normalized_value text NOT NULL,
  source_system_code text REFERENCES public.source_systems(code) ON DELETE RESTRICT,
  registration_office_id uuid REFERENCES public.registration_offices(id) ON DELETE RESTRICT,
  geographic_area_id uuid REFERENCES public.geographic_areas(id) ON DELETE RESTRICT,
  development_project_id uuid REFERENCES public.development_projects(id) ON DELETE RESTRICT,
  development_phase_id uuid,
  source_reference text,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (development_phase_id, development_project_id)
    REFERENCES public.development_phases (id, development_project_id)
    ON DELETE RESTRICT,
  UNIQUE NULLS NOT DISTINCT (
    source_system_code,
    registration_office_id,
    identifier_type,
    normalized_value,
    geographic_area_id,
    development_project_id,
    development_phase_id
  ),
  CHECK (length(btrim(raw_value)) > 0),
  CHECK (length(btrim(normalized_value)) > 0)
);

CREATE TABLE public.residential_unit_details (
  property_id uuid PRIMARY KEY REFERENCES public.properties(id) ON DELETE CASCADE,
  block_label text,
  unit_number text,
  built_area_sqft numeric(12, 2) CHECK (built_area_sqft IS NULL OR built_area_sqft >= 0),
  uds_area_sqyd numeric(12, 2) CHECK (uds_area_sqyd IS NULL OR uds_area_sqyd >= 0),
  boundaries text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.land_plot_details (
  property_id uuid PRIMARY KEY REFERENCES public.properties(id) ON DELETE CASCADE,
  plot_number text,
  extent_sqyd numeric(12, 2) CHECK (extent_sqyd IS NULL OR extent_sqyd >= 0),
  built_area_sqft numeric(12, 2) CHECK (built_area_sqft IS NULL OR built_area_sqft >= 0),
  boundaries text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX development_projects_area_idx
  ON public.development_projects (geographic_area_id, normalized_name);

CREATE INDEX properties_type_area_idx
  ON public.properties (property_type_code, geographic_area_id);

CREATE INDEX properties_project_phase_idx
  ON public.properties (development_project_id, development_phase_id);

CREATE INDEX property_identifiers_lookup_idx
  ON public.property_identifiers (identifier_type, normalized_value);

CREATE TRIGGER development_projects_updated_at
  BEFORE UPDATE ON public.development_projects
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER development_phases_updated_at
  BEFORE UPDATE ON public.development_phases
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER properties_updated_at
  BEFORE UPDATE ON public.properties
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER residential_unit_details_updated_at
  BEFORE UPDATE ON public.residential_unit_details
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER land_plot_details_updated_at
  BEFORE UPDATE ON public.land_plot_details
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();