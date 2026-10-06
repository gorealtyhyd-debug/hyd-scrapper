CREATE TABLE public.crm_contacts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  display_name text NOT NULL,
  notes text,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (length(btrim(display_name)) > 0)
);

CREATE TABLE public.crm_contact_methods (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  contact_id uuid NOT NULL REFERENCES public.crm_contacts(id) ON DELETE CASCADE,
  method_type text NOT NULL CHECK (method_type IN ('mobile', 'email')),
  raw_value text NOT NULL,
  normalized_value text NOT NULL,
  consent_status text NOT NULL DEFAULT 'unknown' CHECK (consent_status IN ('unknown', 'opt_in', 'opt_out')),
  is_primary boolean NOT NULL DEFAULT false,
  source_reference text,
  verified_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (length(btrim(raw_value)) > 0),
  CHECK (length(btrim(normalized_value)) > 0)
);

CREATE INDEX crm_contact_methods_lookup_idx
  ON public.crm_contact_methods (method_type, normalized_value);

CREATE TABLE public.mobile_captures (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id uuid REFERENCES public.properties(id) ON DELETE RESTRICT,
  registration_document_id uuid REFERENCES public.registration_documents(id) ON DELETE RESTRICT,
  contact_id uuid REFERENCES public.crm_contacts(id) ON DELETE SET NULL,
  captured_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  phone_as_captured text NOT NULL,
  normalized_phone text,
  capture_source text NOT NULL,
  note text,
  captured_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (property_id IS NOT NULL OR registration_document_id IS NOT NULL),
  CHECK (length(btrim(phone_as_captured)) > 0),
  CHECK (length(btrim(capture_source)) > 0)
);

CREATE INDEX mobile_captures_property_time_idx
  ON public.mobile_captures (property_id, captured_at DESC);

CREATE INDEX mobile_captures_document_time_idx
  ON public.mobile_captures (registration_document_id, captured_at DESC);

CREATE TABLE public.leads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id uuid NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
  contact_id uuid REFERENCES public.crm_contacts(id) ON DELETE SET NULL,
  lead_status_code text NOT NULL REFERENCES public.lead_statuses(code) ON DELETE RESTRICT,
  qualification_notes text,
  expected_sale_price numeric(14, 2) CHECK (expected_sale_price IS NULL OR expected_sale_price >= 0),
  expected_monthly_rent numeric(14, 2) CHECK (expected_monthly_rent IS NULL OR expected_monthly_rent >= 0),
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.lead_status_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_sequence bigint GENERATED ALWAYS AS IDENTITY UNIQUE,
  lead_id uuid NOT NULL REFERENCES public.leads(id) ON DELETE RESTRICT,
  from_status_code text REFERENCES public.lead_statuses(code) ON DELETE RESTRICT,
  to_status_code text NOT NULL REFERENCES public.lead_statuses(code) ON DELETE RESTRICT,
  actor_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reason text,
  event_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE public.lead_follow_ups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id uuid NOT NULL REFERENCES public.leads(id) ON DELETE RESTRICT,
  assigned_to uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  scheduled_at timestamptz NOT NULL,
  follow_up_status text NOT NULL DEFAULT 'scheduled' CHECK (follow_up_status IN ('scheduled', 'completed', 'cancelled', 'missed')),
  note text,
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (completed_at IS NULL OR follow_up_status = 'completed')
);

CREATE INDEX leads_property_status_idx
  ON public.leads (property_id, lead_status_code);

CREATE INDEX lead_follow_ups_due_idx
  ON public.lead_follow_ups (follow_up_status, scheduled_at);

CREATE OR REPLACE FUNCTION public.record_lead_status_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.lead_status_history (lead_id, to_status_code, actor_user_id)
    VALUES (NEW.id, NEW.lead_status_code, auth.uid());
  ELSIF NEW.lead_status_code IS DISTINCT FROM OLD.lead_status_code THEN
    INSERT INTO public.lead_status_history
      (lead_id, from_status_code, to_status_code, actor_user_id)
    VALUES (NEW.id, OLD.lead_status_code, NEW.lead_status_code, auth.uid());
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER leads_record_initial_status
  AFTER INSERT ON public.leads
  FOR EACH ROW EXECUTE FUNCTION public.record_lead_status_change();

CREATE TRIGGER leads_record_status_change
  AFTER UPDATE OF lead_status_code ON public.leads
  FOR EACH ROW EXECUTE FUNCTION public.record_lead_status_change();

CREATE TRIGGER crm_contacts_updated_at
  BEFORE UPDATE ON public.crm_contacts
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER leads_updated_at
  BEFORE UPDATE ON public.leads
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER lead_follow_ups_updated_at
  BEFORE UPDATE ON public.lead_follow_ups
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();