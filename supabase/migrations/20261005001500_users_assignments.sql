CREATE TABLE public.user_profiles (
  auth_user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE RESTRICT,
  display_name text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (length(btrim(display_name)) > 0)
);

CREATE TABLE public.permissions (
  code text PRIMARY KEY CHECK (code ~ '^[a-z][a-z0-9_.]*$'),
  label text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.role_permissions (
  role_code text NOT NULL REFERENCES public.access_roles(code) ON DELETE RESTRICT,
  permission_code text NOT NULL REFERENCES public.permissions(code) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (role_code, permission_code)
);

CREATE TABLE public.user_role_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_user_id uuid NOT NULL REFERENCES public.user_profiles(auth_user_id) ON DELETE RESTRICT,
  role_code text NOT NULL REFERENCES public.access_roles(code) ON DELETE RESTRICT,
  assigned_by uuid REFERENCES public.user_profiles(auth_user_id) ON DELETE SET NULL,
  assigned_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (auth_user_id, role_code)
);

CREATE TABLE public.project_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_user_id uuid NOT NULL REFERENCES public.user_profiles(auth_user_id) ON DELETE RESTRICT,
  development_project_id uuid NOT NULL REFERENCES public.development_projects(id) ON DELETE RESTRICT,
  assigned_by uuid REFERENCES public.user_profiles(auth_user_id) ON DELETE SET NULL,
  assigned_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (auth_user_id, development_project_id)
);

CREATE TABLE public.property_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_user_id uuid NOT NULL REFERENCES public.user_profiles(auth_user_id) ON DELETE RESTRICT,
  property_id uuid NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
  assigned_by uuid REFERENCES public.user_profiles(auth_user_id) ON DELETE SET NULL,
  assigned_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (auth_user_id, property_id)
);

INSERT INTO public.permissions (code, label) VALUES
  ('inventory.read', 'Read permitted property inventory'),
  ('inventory.manage', 'Manage property inventory'),
  ('listing.read', 'Read permitted listings'),
  ('listing.manage', 'Manage listings'),
  ('lead.read', 'Read permitted leads'),
  ('lead.qualify', 'Qualify leads'),
  ('sales.manage', 'Manage sales-ready leads'),
  ('capture.write', 'Write assigned mobile captures'),
  ('source.read', 'Read source observations'),
  ('analytics.read', 'Read approved analytics');

INSERT INTO public.role_permissions (role_code, permission_code)
SELECT 'admin', code FROM public.permissions
ON CONFLICT DO NOTHING;

INSERT INTO public.role_permissions (role_code, permission_code) VALUES
  ('telecaller', 'inventory.read'),
  ('telecaller', 'lead.read'),
  ('telecaller', 'lead.qualify'),
  ('telecaller', 'capture.write'),
  ('sales_representative', 'inventory.read'),
  ('sales_representative', 'listing.read'),
  ('sales_representative', 'lead.read'),
  ('sales_representative', 'sales.manage'),
  ('third_party', 'inventory.read'),
  ('third_party', 'capture.write')
ON CONFLICT DO NOTHING;

CREATE INDEX user_role_assignments_user_idx
  ON public.user_role_assignments (auth_user_id, role_code);

CREATE INDEX project_assignments_project_idx
  ON public.project_assignments (development_project_id, auth_user_id);

CREATE INDEX property_assignments_property_idx
  ON public.property_assignments (property_id, auth_user_id);

CREATE TRIGGER user_profiles_updated_at
  BEFORE UPDATE ON public.user_profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();