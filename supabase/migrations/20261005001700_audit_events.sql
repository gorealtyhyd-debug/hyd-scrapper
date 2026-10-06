CREATE TABLE public.audit_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_sequence bigint GENERATED ALWAYS AS IDENTITY UNIQUE,
  actor_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  entity_type text NOT NULL,
  entity_id uuid NOT NULL,
  event_type text NOT NULL,
  before_summary jsonb,
  after_summary jsonb,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(metadata) = 'object'),
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX audit_events_entity_timeline_idx
  ON public.audit_events (entity_type, entity_id, event_sequence);

CREATE INDEX audit_events_actor_time_idx
  ON public.audit_events (actor_user_id, occurred_at DESC);

CREATE OR REPLACE FUNCTION public.write_audit_event(
  target_type text,
  target_id uuid,
  action text,
  old_summary jsonb DEFAULT NULL,
  new_summary jsonb DEFAULT NULL,
  event_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
BEGIN
  INSERT INTO public.audit_events
    (actor_user_id, entity_type, entity_id, event_type, before_summary, after_summary, metadata)
  VALUES
    (auth.uid(), target_type, target_id, action, old_summary, new_summary, COALESCE(event_metadata, '{}'::jsonb));
END;
$$;

CREATE OR REPLACE FUNCTION public.audit_listing_state()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM public.write_audit_event(
      'property_listing', NEW.id, 'created', NULL,
      jsonb_build_object('property_id', NEW.property_id, 'status', NEW.listing_status_code)
    );
  ELSIF NEW.listing_status_code IS DISTINCT FROM OLD.listing_status_code THEN
    PERFORM public.write_audit_event(
      'property_listing', NEW.id, 'status_changed',
      jsonb_build_object('status', OLD.listing_status_code),
      jsonb_build_object('status', NEW.listing_status_code)
    );
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.audit_lead_state()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM public.write_audit_event(
      'lead', NEW.id, 'created', NULL,
      jsonb_build_object('property_id', NEW.property_id, 'status', NEW.lead_status_code)
    );
  ELSIF NEW.lead_status_code IS DISTINCT FROM OLD.lead_status_code THEN
    PERFORM public.write_audit_event(
      'lead', NEW.id, 'status_changed',
      jsonb_build_object('status', OLD.lead_status_code),
      jsonb_build_object('status', NEW.lead_status_code)
    );
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.audit_assignment_or_match_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
DECLARE
  target_id uuid;
  old_data jsonb;
  new_data jsonb;
BEGIN
  IF TG_OP = 'DELETE' THEN
    target_id := OLD.id;
    old_data := to_jsonb(OLD) - 'created_at';
  ELSE
    target_id := NEW.id;
    new_data := to_jsonb(NEW) - 'created_at';
    IF TG_OP = 'UPDATE' THEN
      old_data := to_jsonb(OLD) - 'created_at';
    END IF;
  END IF;

  PERFORM public.write_audit_event(
    TG_TABLE_NAME,
    target_id,
    lower(TG_OP),
    old_data,
    new_data
  );

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.audit_source_promotion()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
BEGIN
  IF NEW.parse_status IS DISTINCT FROM OLD.parse_status THEN
    PERFORM public.write_audit_event(
      'source_observation', NEW.id, 'parse_status_changed',
      jsonb_build_object('parse_status', OLD.parse_status),
      jsonb_build_object('parse_status', NEW.parse_status),
      jsonb_build_object(
        'source_system_code', NEW.source_system_code,
        'source_record_type', NEW.source_record_type,
        'content_hash', NEW.content_hash
      )
    );
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.audit_mobile_capture()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
BEGIN
  PERFORM public.write_audit_event(
    'mobile_capture', NEW.id, 'captured', NULL,
    jsonb_build_object('property_id', NEW.property_id, 'registration_document_id', NEW.registration_document_id)
  );
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.reject_audit_event_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'audit events are append-only';
END;
$$;

CREATE TRIGGER property_listings_audit
  AFTER INSERT OR UPDATE OF listing_status_code ON public.property_listings
  FOR EACH ROW EXECUTE FUNCTION public.audit_listing_state();
CREATE TRIGGER leads_audit
  AFTER INSERT OR UPDATE OF lead_status_code ON public.leads
  FOR EACH ROW EXECUTE FUNCTION public.audit_lead_state();
CREATE TRIGGER user_roles_audit
  AFTER INSERT OR UPDATE OR DELETE ON public.user_role_assignments
  FOR EACH ROW EXECUTE FUNCTION public.audit_assignment_or_match_change();
CREATE TRIGGER project_assignments_audit
  AFTER INSERT OR UPDATE OR DELETE ON public.project_assignments
  FOR EACH ROW EXECUTE FUNCTION public.audit_assignment_or_match_change();
CREATE TRIGGER property_assignments_audit
  AFTER INSERT OR UPDATE OR DELETE ON public.property_assignments
  FOR EACH ROW EXECUTE FUNCTION public.audit_assignment_or_match_change();
CREATE TRIGGER property_survey_matches_audit
  AFTER INSERT OR UPDATE OR DELETE ON public.property_survey_identifiers
  FOR EACH ROW EXECUTE FUNCTION public.audit_assignment_or_match_change();
CREATE TRIGGER schedule_property_matches_audit
  AFTER INSERT OR UPDATE OR DELETE ON public.registration_schedule_property_matches
  FOR EACH ROW EXECUTE FUNCTION public.audit_assignment_or_match_change();
CREATE TRIGGER rera_project_matches_audit
  AFTER INSERT OR UPDATE OR DELETE ON public.rera_project_matches
  FOR EACH ROW EXECUTE FUNCTION public.audit_assignment_or_match_change();
CREATE TRIGGER source_observations_promotion_audit
  AFTER UPDATE OF parse_status ON public.source_observations
  FOR EACH ROW EXECUTE FUNCTION public.audit_source_promotion();
CREATE TRIGGER mobile_captures_audit
  AFTER INSERT ON public.mobile_captures
  FOR EACH ROW EXECUTE FUNCTION public.audit_mobile_capture();
CREATE TRIGGER audit_events_append_only
  BEFORE UPDATE OR DELETE ON public.audit_events
  FOR EACH ROW EXECUTE FUNCTION public.reject_audit_event_mutation();

ALTER TABLE public.audit_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY audit_admin_read ON public.audit_events
  FOR SELECT TO authenticated
  USING (public.current_user_has_role('admin'));

REVOKE ALL ON FUNCTION public.write_audit_event(text, uuid, text, jsonb, jsonb, jsonb) FROM PUBLIC;
GRANT SELECT ON public.audit_events TO authenticated;