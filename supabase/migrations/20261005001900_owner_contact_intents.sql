CREATE TABLE public.contact_method_sources (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  contact_method_id uuid NOT NULL REFERENCES public.crm_contact_methods(id) ON DELETE RESTRICT,
  source_name text NOT NULL,
  source_reference text,
  source_observation jsonb NOT NULL DEFAULT '{}'::jsonb
    CHECK (jsonb_typeof(source_observation) = 'object'),
  verification_status text NOT NULL DEFAULT 'candidate'
    CHECK (verification_status IN ('candidate', 'verified', 'rejected')),
  captured_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  collected_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE NULLS NOT DISTINCT (contact_method_id, source_name, source_reference),
  CHECK (length(btrim(source_name)) > 0)
);

CREATE TABLE public.property_contact_matches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id uuid NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
  contact_method_id uuid NOT NULL REFERENCES public.crm_contact_methods(id) ON DELETE RESTRICT,
  party_id uuid REFERENCES public.parties(id) ON DELETE RESTRICT,
  registration_document_party_id uuid REFERENCES public.registration_document_parties(id) ON DELETE RESTRICT,
  match_status text NOT NULL DEFAULT 'candidate'
    CHECK (match_status IN ('candidate', 'confirmed', 'rejected')),
  match_method text NOT NULL
    CHECK (match_method IN ('external_source', 'owner_call', 'document_reference', 'manual_review')),
  confidence numeric(5, 4) CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1),
  source_reference text,
  reviewed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (registration_document_party_id IS NULL OR party_id IS NOT NULL),
  UNIQUE NULLS NOT DISTINCT (property_id, contact_method_id, source_reference)
);

CREATE INDEX property_contact_matches_property_idx
  ON public.property_contact_matches (property_id, match_status);

CREATE INDEX property_contact_matches_contact_method_idx
  ON public.property_contact_matches (contact_method_id, match_status);

CREATE TABLE public.owner_intents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_contact_match_id uuid NOT NULL REFERENCES public.property_contact_matches(id) ON DELETE RESTRICT,
  intent_type text NOT NULL CHECK (intent_type IN ('sale', 'rent')),
  cycle_number integer NOT NULL DEFAULT 1 CHECK (cycle_number > 0),
  workflow_status text NOT NULL DEFAULT 'queued'
    CHECK (workflow_status IN (
      'queued', 'contacting', 'interested', 'not_interested', 'callback_requested',
      'unreachable', 'wrong_number', 'opted_out', 'converted', 'closed'
    )),
  expected_amount numeric(14, 2) CHECK (expected_amount IS NULL OR expected_amount >= 0),
  currency_code text NOT NULL DEFAULT 'INR' CHECK (currency_code ~ '^[A-Z]{3}$'),
  rent_period text CHECK (rent_period IS NULL OR rent_period IN ('day', 'week', 'month', 'year')),
  intent_confirmed_at timestamptz,
  confirmed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  notes text,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (property_contact_match_id, intent_type, cycle_number),
  CHECK ((intent_type = 'rent') OR rent_period IS NULL),
  CHECK (workflow_status <> 'interested' OR intent_confirmed_at IS NOT NULL)
);

CREATE INDEX owner_intents_property_type_status_idx
  ON public.owner_intents (property_contact_match_id, intent_type, workflow_status);

CREATE INDEX owner_intents_call_queue_idx
  ON public.owner_intents (workflow_status, updated_at)
  WHERE workflow_status IN ('queued', 'callback_requested', 'unreachable');

CREATE TABLE public.owner_intent_status_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_sequence bigint GENERATED ALWAYS AS IDENTITY UNIQUE,
  owner_intent_id uuid NOT NULL REFERENCES public.owner_intents(id) ON DELETE RESTRICT,
  from_status text,
  to_status text NOT NULL,
  actor_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reason text,
  event_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE public.owner_intent_call_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_intent_id uuid NOT NULL REFERENCES public.owner_intents(id) ON DELETE RESTRICT,
  attempted_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  attempted_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  call_outcome text NOT NULL CHECK (call_outcome IN (
    'connected_interested', 'connected_not_interested', 'callback_requested',
    'no_answer', 'busy', 'wrong_number', 'wrong_person', 'opted_out', 'other'
  )),
  duration_seconds integer CHECK (duration_seconds IS NULL OR duration_seconds >= 0),
  notes text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX owner_intent_call_attempts_timeline_idx
  ON public.owner_intent_call_attempts (owner_intent_id, attempted_at DESC);

CREATE OR REPLACE FUNCTION public.current_user_can_access_contact_method(target_contact_method_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
  SELECT public.current_user_has_role('admin') OR (
    public.current_user_has_permission('lead.qualify')
    AND NOT public.current_user_has_role('third_party')
    AND EXISTS (
      SELECT 1 FROM public.property_contact_matches AS match
      WHERE match.contact_method_id = target_contact_method_id
        AND public.current_user_has_property_assignment(match.property_id)
    )
  )
$$;

CREATE OR REPLACE FUNCTION public.current_user_can_access_owner_intent(target_owner_intent_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
  SELECT public.current_user_has_role('admin') OR (
    public.current_user_has_permission('lead.read')
    AND NOT public.current_user_has_role('third_party')
    AND EXISTS (
      SELECT 1
      FROM public.owner_intents AS intent
      JOIN public.property_contact_matches AS match
        ON match.id = intent.property_contact_match_id
      WHERE intent.id = target_owner_intent_id
        AND public.current_user_has_property_assignment(match.property_id)
    )
  )
$$;

CREATE OR REPLACE FUNCTION public.current_user_can_read_contact(target_contact_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
  SELECT public.current_user_has_role('admin') OR EXISTS (
    SELECT 1 FROM public.leads AS lead
    WHERE lead.contact_id = target_contact_id
      AND public.current_user_can_read_lead(lead.property_id, lead.lead_status_code)
  ) OR (
    public.current_user_has_permission('lead.qualify')
    AND NOT public.current_user_has_role('third_party')
    AND EXISTS (
      SELECT 1
      FROM public.crm_contact_methods AS method
      JOIN public.property_contact_matches AS match
        ON match.contact_method_id = method.id
      WHERE method.contact_id = target_contact_id
        AND public.current_user_has_property_assignment(match.property_id)
    )
  )
$$;

CREATE OR REPLACE FUNCTION public.record_owner_intent_status_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.owner_intent_status_history
      (owner_intent_id, to_status, actor_user_id)
    VALUES (NEW.id, NEW.workflow_status, auth.uid());
  ELSIF NEW.workflow_status IS DISTINCT FROM OLD.workflow_status THEN
    INSERT INTO public.owner_intent_status_history
      (owner_intent_id, from_status, to_status, actor_user_id)
    VALUES (NEW.id, OLD.workflow_status, NEW.workflow_status, auth.uid());
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_contact_method_source_actor()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
BEGIN
  NEW.captured_by = auth.uid();
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_property_contact_match_reviewer()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
BEGIN
  IF TG_OP = 'INSERT' AND NEW.match_status <> 'candidate' THEN
    NEW.reviewed_by = auth.uid();
    NEW.reviewed_at = clock_timestamp();
  ELSIF TG_OP = 'UPDATE' AND NEW.match_status IS DISTINCT FROM OLD.match_status THEN
    NEW.reviewed_by = auth.uid();
    NEW.reviewed_at = clock_timestamp();
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_owner_intent_actor()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.created_by = auth.uid();
  END IF;
  IF NEW.workflow_status = 'interested'
     AND (TG_OP = 'INSERT' OR NEW.workflow_status IS DISTINCT FROM OLD.workflow_status) THEN
    NEW.intent_confirmed_at = COALESCE(NEW.intent_confirmed_at, clock_timestamp());
    NEW.confirmed_by = auth.uid();
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_owner_intent_call_actor()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
BEGIN
  NEW.attempted_by = auth.uid();
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.reject_owner_intent_history_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'owner intent history is append-only';
END;
$$;

CREATE OR REPLACE FUNCTION public.audit_owner_intent_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
DECLARE
  old_summary jsonb;
  new_summary jsonb;
  target_id uuid;
  action text;
BEGIN
  IF TG_OP = 'DELETE' THEN
    target_id := OLD.id;
    old_summary := jsonb_build_object('intent_type', OLD.intent_type, 'workflow_status', OLD.workflow_status);
  ELSE
    target_id := NEW.id;
    new_summary := jsonb_build_object('intent_type', NEW.intent_type, 'workflow_status', NEW.workflow_status);
    IF TG_OP = 'UPDATE' THEN
      old_summary := jsonb_build_object('intent_type', OLD.intent_type, 'workflow_status', OLD.workflow_status);
    END IF;
  END IF;
  action := CASE WHEN TG_OP = 'INSERT' THEN 'created' WHEN TG_OP = 'UPDATE' THEN 'updated' ELSE 'deleted' END;
  PERFORM public.write_audit_event('owner_intent', target_id, action, old_summary, new_summary);
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.audit_owner_intent_call()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
BEGIN
  PERFORM public.write_audit_event(
    'owner_intent_call_attempt', NEW.id, 'call_attempted', NULL,
    jsonb_build_object('owner_intent_id', NEW.owner_intent_id, 'call_outcome', NEW.call_outcome)
  );
  RETURN NEW;
END;
$$;

CREATE TRIGGER contact_method_sources_set_actor
  BEFORE INSERT ON public.contact_method_sources
  FOR EACH ROW EXECUTE FUNCTION public.set_contact_method_source_actor();

CREATE TRIGGER property_contact_matches_set_reviewer
  BEFORE INSERT OR UPDATE OF match_status ON public.property_contact_matches
  FOR EACH ROW EXECUTE FUNCTION public.set_property_contact_match_reviewer();

CREATE TRIGGER owner_intents_set_actor
  BEFORE INSERT OR UPDATE OF workflow_status ON public.owner_intents
  FOR EACH ROW EXECUTE FUNCTION public.set_owner_intent_actor();

CREATE TRIGGER owner_intents_record_initial_status
  AFTER INSERT ON public.owner_intents
  FOR EACH ROW EXECUTE FUNCTION public.record_owner_intent_status_change();

CREATE TRIGGER owner_intents_record_status_change
  AFTER UPDATE OF workflow_status ON public.owner_intents
  FOR EACH ROW EXECUTE FUNCTION public.record_owner_intent_status_change();

CREATE TRIGGER owner_intents_updated_at
  BEFORE UPDATE ON public.owner_intents
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER owner_intent_calls_set_actor
  BEFORE INSERT ON public.owner_intent_call_attempts
  FOR EACH ROW EXECUTE FUNCTION public.set_owner_intent_call_actor();

CREATE TRIGGER owner_intent_call_attempts_append_only
  BEFORE UPDATE OR DELETE ON public.owner_intent_call_attempts
  FOR EACH ROW EXECUTE FUNCTION public.reject_owner_intent_history_mutation();

CREATE TRIGGER owner_intent_status_history_append_only
  BEFORE UPDATE OR DELETE ON public.owner_intent_status_history
  FOR EACH ROW EXECUTE FUNCTION public.reject_owner_intent_history_mutation();

CREATE TRIGGER owner_intent_calls_audit
  AFTER INSERT ON public.owner_intent_call_attempts
  FOR EACH ROW EXECUTE FUNCTION public.audit_owner_intent_call();

CREATE TRIGGER property_contact_matches_audit
  AFTER INSERT OR UPDATE OR DELETE ON public.property_contact_matches
  FOR EACH ROW EXECUTE FUNCTION public.audit_assignment_or_match_change();

CREATE TRIGGER owner_intents_audit
  AFTER INSERT OR UPDATE OR DELETE ON public.owner_intents
  FOR EACH ROW EXECUTE FUNCTION public.audit_owner_intent_change();

ALTER TABLE public.contact_method_sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.property_contact_matches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.owner_intents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.owner_intent_status_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.owner_intent_call_attempts ENABLE ROW LEVEL SECURITY;

CREATE POLICY contact_method_source_read ON public.contact_method_sources
  FOR SELECT TO authenticated
  USING (public.current_user_can_access_contact_method(contact_method_id));

CREATE POLICY contact_method_source_manage ON public.contact_method_sources
  FOR ALL TO authenticated
  USING (public.current_user_can_access_contact_method(contact_method_id))
  WITH CHECK (public.current_user_can_access_contact_method(contact_method_id));

CREATE POLICY property_contact_match_read ON public.property_contact_matches
  FOR SELECT TO authenticated
  USING (
    public.current_user_has_role('admin')
    OR (public.current_user_has_permission('lead.read')
        AND NOT public.current_user_has_role('third_party')
        AND public.current_user_has_property_assignment(property_id))
  );

CREATE POLICY property_contact_match_manage ON public.property_contact_matches
  FOR ALL TO authenticated
  USING (
    public.current_user_has_role('admin')
    OR (public.current_user_has_permission('lead.qualify')
        AND NOT public.current_user_has_role('third_party')
        AND public.current_user_has_property_assignment(property_id))
  )
  WITH CHECK (
    public.current_user_has_role('admin')
    OR (public.current_user_has_permission('lead.qualify')
        AND NOT public.current_user_has_role('third_party')
        AND public.current_user_has_property_assignment(property_id))
  );

CREATE POLICY owner_intent_read ON public.owner_intents
  FOR SELECT TO authenticated
  USING (public.current_user_can_access_owner_intent(id));

CREATE POLICY owner_intent_manage ON public.owner_intents
  FOR ALL TO authenticated
  USING (
    public.current_user_has_role('admin')
    OR (public.current_user_has_permission('lead.qualify')
        AND NOT public.current_user_has_role('third_party')
        AND EXISTS (
          SELECT 1 FROM public.property_contact_matches AS match
          WHERE match.id = property_contact_match_id
            AND public.current_user_has_property_assignment(match.property_id)
        ))
  )
  WITH CHECK (
    public.current_user_has_role('admin')
    OR (public.current_user_has_permission('lead.qualify')
        AND NOT public.current_user_has_role('third_party')
        AND EXISTS (
          SELECT 1 FROM public.property_contact_matches AS match
          WHERE match.id = property_contact_match_id
            AND public.current_user_has_property_assignment(match.property_id)
        ))
  );

CREATE POLICY owner_intent_history_read ON public.owner_intent_status_history
  FOR SELECT TO authenticated
  USING (public.current_user_can_access_owner_intent(owner_intent_id));

CREATE POLICY owner_intent_calls_read ON public.owner_intent_call_attempts
  FOR SELECT TO authenticated
  USING (public.current_user_can_access_owner_intent(owner_intent_id));

CREATE POLICY owner_intent_calls_insert ON public.owner_intent_call_attempts
  FOR INSERT TO authenticated
  WITH CHECK (
    attempted_by = auth.uid()
    AND public.current_user_has_permission('lead.qualify')
    AND NOT public.current_user_has_role('third_party')
    AND public.current_user_can_access_owner_intent(owner_intent_id)
  );

CREATE VIEW public.property_owner_intents_read
WITH (security_barrier = true)
AS
SELECT
  intent.id AS owner_intent_id,
  match.property_id,
  match.party_id,
  match.contact_method_id,
  match.match_status AS contact_match_status,
  method.normalized_value AS phone_number,
  intent.intent_type,
  intent.workflow_status,
  intent.expected_amount,
  intent.currency_code,
  intent.rent_period,
  intent.intent_confirmed_at,
  intent.updated_at
FROM public.owner_intents AS intent
JOIN public.property_contact_matches AS match
  ON match.id = intent.property_contact_match_id
JOIN public.crm_contact_methods AS method
  ON method.id = match.contact_method_id
WHERE public.current_user_can_access_owner_intent(intent.id);

GRANT EXECUTE ON FUNCTION public.current_user_can_access_contact_method(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_user_can_access_owner_intent(uuid) TO authenticated;
GRANT SELECT ON
  public.contact_method_sources,
  public.property_contact_matches,
  public.owner_intents
TO authenticated;
GRANT INSERT (contact_method_id, source_name, source_reference, source_observation, verification_status)
  ON public.contact_method_sources TO authenticated;
GRANT UPDATE (verification_status)
  ON public.contact_method_sources TO authenticated;
GRANT INSERT (property_id, contact_method_id, party_id, registration_document_party_id,
              match_status, match_method, confidence, source_reference)
  ON public.property_contact_matches TO authenticated;
GRANT UPDATE (party_id, registration_document_party_id, match_status, match_method, confidence, source_reference)
  ON public.property_contact_matches TO authenticated;
GRANT INSERT (property_contact_match_id, intent_type, cycle_number, workflow_status,
              expected_amount, currency_code, rent_period, notes)
  ON public.owner_intents TO authenticated;
GRANT UPDATE (workflow_status, expected_amount, currency_code, rent_period, notes)
  ON public.owner_intents TO authenticated;
GRANT SELECT ON
  public.owner_intent_status_history,
  public.owner_intent_call_attempts,
  public.property_owner_intents_read
TO authenticated;
GRANT INSERT (owner_intent_id, call_outcome, duration_seconds, notes)
  ON public.owner_intent_call_attempts TO authenticated;