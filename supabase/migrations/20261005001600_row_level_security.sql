CREATE OR REPLACE FUNCTION public.current_user_has_role(required_role text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_role_assignments AS assignment
    JOIN public.user_profiles AS profile ON profile.auth_user_id = assignment.auth_user_id
    WHERE assignment.auth_user_id = auth.uid()
      AND assignment.role_code = required_role
      AND profile.is_active
  )
$$;

CREATE OR REPLACE FUNCTION public.current_user_has_permission(required_permission text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_role_assignments AS assignment
    JOIN public.user_profiles AS profile ON profile.auth_user_id = assignment.auth_user_id
    JOIN public.role_permissions AS permission ON permission.role_code = assignment.role_code
    WHERE assignment.auth_user_id = auth.uid()
      AND permission.permission_code = required_permission
      AND profile.is_active
  )
$$;

CREATE OR REPLACE FUNCTION public.current_user_has_project_assignment(project_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.project_assignments
    WHERE auth_user_id = auth.uid() AND development_project_id = project_id
  ) OR EXISTS (
    SELECT 1
    FROM public.property_assignments AS assignment
    JOIN public.properties AS property ON property.id = assignment.property_id
    WHERE assignment.auth_user_id = auth.uid()
      AND property.development_project_id = project_id
  )
$$;

CREATE OR REPLACE FUNCTION public.current_user_has_property_assignment(target_property_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.property_assignments
    WHERE auth_user_id = auth.uid() AND property_id = target_property_id
  ) OR EXISTS (
    SELECT 1
    FROM public.properties AS property
    JOIN public.project_assignments AS assignment
      ON assignment.development_project_id = property.development_project_id
    WHERE property.id = target_property_id
      AND assignment.auth_user_id = auth.uid()
  )
$$;

CREATE OR REPLACE FUNCTION public.current_user_can_read_lead(target_property_id uuid, target_status text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
  SELECT public.current_user_has_role('admin') OR (
    public.current_user_has_permission('lead.read')
    AND public.current_user_has_property_assignment(target_property_id)
    AND (
      NOT public.current_user_has_role('sales_representative')
      OR target_status IN ('resale', 'rent')
    )
  )
$$;

CREATE OR REPLACE FUNCTION public.current_user_can_read_lead_id(target_lead_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.leads AS lead
    WHERE lead.id = target_lead_id
      AND public.current_user_can_read_lead(lead.property_id, lead.lead_status_code)
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
  )
$$;

CREATE OR REPLACE FUNCTION public.set_mobile_capture_actor()
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

CREATE TRIGGER mobile_captures_set_actor
  BEFORE INSERT ON public.mobile_captures
  FOR EACH ROW EXECUTE FUNCTION public.set_mobile_capture_actor();

ALTER TABLE public.source_systems ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.property_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.listing_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.listing_statuses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.party_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lead_statuses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.access_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.geographic_areas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.geographic_area_aliases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.registration_offices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.survey_identifiers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.survey_identifier_aliases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.survey_identifier_relations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.development_projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.development_project_aliases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.development_phases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.properties ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.property_aliases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.property_identifiers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.residential_unit_details ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.land_plot_details ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.property_survey_identifiers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.property_listings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.property_listing_status_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.import_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.source_observations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.source_observation_sightings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.registration_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.registration_document_observations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.registration_schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.registration_schedule_observations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.parties ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.party_aliases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.registration_document_parties ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.registration_schedule_property_matches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.registration_document_relations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rera_registrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rera_registration_observations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rera_project_matches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_contact_methods ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mobile_captures ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.leads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lead_status_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lead_follow_ups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.role_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_role_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.project_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.property_assignments ENABLE ROW LEVEL SECURITY;

CREATE POLICY authenticated_reference_read ON public.property_types
  FOR SELECT TO authenticated USING (auth.uid() IS NOT NULL);
CREATE POLICY authenticated_document_type_read ON public.document_types
  FOR SELECT TO authenticated USING (auth.uid() IS NOT NULL);
CREATE POLICY authenticated_listing_type_read ON public.listing_types
  FOR SELECT TO authenticated USING (auth.uid() IS NOT NULL);
CREATE POLICY authenticated_listing_status_read ON public.listing_statuses
  FOR SELECT TO authenticated USING (auth.uid() IS NOT NULL);
CREATE POLICY authenticated_party_role_read ON public.party_roles
  FOR SELECT TO authenticated USING (auth.uid() IS NOT NULL);
CREATE POLICY authenticated_lead_status_read ON public.lead_statuses
  FOR SELECT TO authenticated USING (auth.uid() IS NOT NULL);
CREATE POLICY authenticated_access_role_read ON public.access_roles
  FOR SELECT TO authenticated USING (auth.uid() IS NOT NULL);
CREATE POLICY authenticated_permission_read ON public.permissions
  FOR SELECT TO authenticated USING (auth.uid() IS NOT NULL);
CREATE POLICY authenticated_role_permission_read ON public.role_permissions
  FOR SELECT TO authenticated USING (auth.uid() IS NOT NULL);

CREATE POLICY source_system_admin_access ON public.source_systems
  FOR ALL TO authenticated
  USING (public.current_user_has_permission('source.read'))
  WITH CHECK (public.current_user_has_permission('source.read'));

CREATE POLICY geographic_inventory_read ON public.geographic_areas
  FOR SELECT TO authenticated USING (public.current_user_has_permission('inventory.read'));
CREATE POLICY geographic_alias_admin_access ON public.geographic_area_aliases
  FOR ALL TO authenticated
  USING (public.current_user_has_role('admin'))
  WITH CHECK (public.current_user_has_role('admin'));
CREATE POLICY registration_office_inventory_read ON public.registration_offices
  FOR SELECT TO authenticated USING (public.current_user_has_permission('inventory.read'));

CREATE POLICY project_assignment_read ON public.development_projects
  FOR SELECT TO authenticated
  USING (
    public.current_user_has_role('admin')
    OR (public.current_user_has_permission('inventory.read') AND public.current_user_has_project_assignment(id))
  );
CREATE POLICY project_admin_write ON public.development_projects
  FOR ALL TO authenticated
  USING (public.current_user_has_role('admin'))
  WITH CHECK (public.current_user_has_role('admin'));
CREATE POLICY phase_assignment_read ON public.development_phases
  FOR SELECT TO authenticated
  USING (
    public.current_user_has_role('admin')
    OR (public.current_user_has_permission('inventory.read') AND public.current_user_has_project_assignment(development_project_id))
  );
CREATE POLICY phase_admin_write ON public.development_phases
  FOR ALL TO authenticated
  USING (public.current_user_has_role('admin'))
  WITH CHECK (public.current_user_has_role('admin'));
CREATE POLICY properties_assignment_read ON public.properties
  FOR SELECT TO authenticated
  USING (
    public.current_user_has_role('admin')
    OR (public.current_user_has_permission('inventory.read') AND public.current_user_has_property_assignment(id))
  );
CREATE POLICY properties_admin_write ON public.properties
  FOR ALL TO authenticated
  USING (public.current_user_has_role('admin'))
  WITH CHECK (public.current_user_has_role('admin'));

CREATE POLICY property_details_internal_read ON public.residential_unit_details
  FOR SELECT TO authenticated
  USING (
    public.current_user_has_role('admin')
    OR (NOT public.current_user_has_role('third_party')
        AND public.current_user_has_permission('inventory.read')
        AND public.current_user_has_property_assignment(property_id))
  );
CREATE POLICY plot_details_internal_read ON public.land_plot_details
  FOR SELECT TO authenticated
  USING (
    public.current_user_has_role('admin')
    OR (NOT public.current_user_has_role('third_party')
        AND public.current_user_has_permission('inventory.read')
        AND public.current_user_has_property_assignment(property_id))
  );
CREATE POLICY property_alias_internal_read ON public.property_aliases
  FOR SELECT TO authenticated
  USING (public.current_user_has_role('admin') OR
    (NOT public.current_user_has_role('third_party') AND public.current_user_has_property_assignment(property_id)));
CREATE POLICY property_identifier_internal_read ON public.property_identifiers
  FOR SELECT TO authenticated
  USING (public.current_user_has_role('admin') OR
    (NOT public.current_user_has_role('third_party') AND public.current_user_has_property_assignment(property_id)));
CREATE POLICY property_survey_internal_read ON public.property_survey_identifiers
  FOR SELECT TO authenticated
  USING (public.current_user_has_role('admin') OR
    (NOT public.current_user_has_role('third_party') AND public.current_user_has_property_assignment(property_id)));

CREATE POLICY listing_assignment_read ON public.property_listings
  FOR SELECT TO authenticated
  USING (
    public.current_user_has_role('admin')
    OR (public.current_user_has_permission('listing.read') AND public.current_user_has_property_assignment(property_id))
  );
CREATE POLICY listing_admin_write ON public.property_listings
  FOR ALL TO authenticated
  USING (public.current_user_has_role('admin'))
  WITH CHECK (public.current_user_has_role('admin'));
CREATE POLICY listing_history_assignment_read ON public.property_listing_status_history
  FOR SELECT TO authenticated
  USING (
    public.current_user_has_role('admin')
    OR EXISTS (
      SELECT 1 FROM public.property_listings AS listing
      WHERE listing.id = property_listing_id
        AND public.current_user_has_permission('listing.read')
        AND public.current_user_has_property_assignment(listing.property_id)
    )
  );

CREATE POLICY source_import_admin_access ON public.import_runs
  FOR ALL TO authenticated
  USING (public.current_user_has_permission('source.read'))
  WITH CHECK (public.current_user_has_permission('source.read'));
CREATE POLICY source_observation_admin_access ON public.source_observations
  FOR ALL TO authenticated
  USING (public.current_user_has_permission('source.read'))
  WITH CHECK (public.current_user_has_permission('source.read'));
CREATE POLICY source_sighting_admin_access ON public.source_observation_sightings
  FOR ALL TO authenticated
  USING (public.current_user_has_permission('source.read'))
  WITH CHECK (public.current_user_has_permission('source.read'));

CREATE POLICY registry_admin_access ON public.registration_documents
  FOR ALL TO authenticated
  USING (public.current_user_has_permission('source.read'))
  WITH CHECK (public.current_user_has_permission('source.read'));
CREATE POLICY document_observation_admin_access ON public.registration_document_observations
  FOR ALL TO authenticated
  USING (public.current_user_has_permission('source.read'))
  WITH CHECK (public.current_user_has_permission('source.read'));
CREATE POLICY schedule_admin_access ON public.registration_schedules
  FOR ALL TO authenticated
  USING (public.current_user_has_permission('source.read'))
  WITH CHECK (public.current_user_has_permission('source.read'));
CREATE POLICY schedule_observation_admin_access ON public.registration_schedule_observations
  FOR ALL TO authenticated
  USING (public.current_user_has_permission('source.read'))
  WITH CHECK (public.current_user_has_permission('source.read'));
CREATE POLICY party_admin_access ON public.parties
  FOR ALL TO authenticated
  USING (public.current_user_has_permission('source.read'))
  WITH CHECK (public.current_user_has_permission('source.read'));
CREATE POLICY party_alias_admin_access ON public.party_aliases
  FOR ALL TO authenticated
  USING (public.current_user_has_permission('source.read'))
  WITH CHECK (public.current_user_has_permission('source.read'));
CREATE POLICY document_party_admin_access ON public.registration_document_parties
  FOR ALL TO authenticated
  USING (public.current_user_has_permission('source.read'))
  WITH CHECK (public.current_user_has_permission('source.read'));
CREATE POLICY schedule_property_internal_read ON public.registration_schedule_property_matches
  FOR SELECT TO authenticated
  USING (
    public.current_user_has_role('admin')
    OR (NOT public.current_user_has_role('third_party')
        AND public.current_user_has_permission('inventory.read')
        AND public.current_user_has_property_assignment(property_id))
  );
CREATE POLICY document_relation_admin_access ON public.registration_document_relations
  FOR ALL TO authenticated
  USING (public.current_user_has_permission('source.read'))
  WITH CHECK (public.current_user_has_permission('source.read'));

CREATE POLICY rera_admin_access ON public.rera_registrations
  FOR ALL TO authenticated
  USING (public.current_user_has_permission('source.read'))
  WITH CHECK (public.current_user_has_permission('source.read'));
CREATE POLICY rera_observation_admin_access ON public.rera_registration_observations
  FOR ALL TO authenticated
  USING (public.current_user_has_permission('source.read'))
  WITH CHECK (public.current_user_has_permission('source.read'));
CREATE POLICY rera_match_admin_access ON public.rera_project_matches
  FOR ALL TO authenticated
  USING (public.current_user_has_permission('source.read'))
  WITH CHECK (public.current_user_has_permission('source.read'));

CREATE POLICY crm_contact_read ON public.crm_contacts
  FOR SELECT TO authenticated
  USING (public.current_user_can_read_contact(id));
CREATE POLICY crm_contact_admin_write ON public.crm_contacts
  FOR ALL TO authenticated
  USING (public.current_user_has_role('admin'))
  WITH CHECK (public.current_user_has_role('admin'));
CREATE POLICY crm_contact_method_read ON public.crm_contact_methods
  FOR SELECT TO authenticated
  USING (public.current_user_can_read_contact(contact_id));
CREATE POLICY crm_contact_method_admin_write ON public.crm_contact_methods
  FOR ALL TO authenticated
  USING (public.current_user_has_role('admin'))
  WITH CHECK (public.current_user_has_role('admin'));

CREATE POLICY mobile_capture_read ON public.mobile_captures
  FOR SELECT TO authenticated
  USING (
    public.current_user_has_role('admin')
    OR (public.current_user_has_permission('lead.read')
        AND public.current_user_has_property_assignment(property_id))
  );
CREATE POLICY mobile_capture_insert ON public.mobile_captures
  FOR INSERT TO authenticated
  WITH CHECK (
    captured_by = auth.uid()
    AND (
      public.current_user_has_role('admin')
      OR (public.current_user_has_permission('capture.write')
          AND public.current_user_has_property_assignment(property_id))
    )
  );

CREATE POLICY lead_assignment_read ON public.leads
  FOR SELECT TO authenticated
  USING (public.current_user_can_read_lead(property_id, lead_status_code));
CREATE POLICY lead_admin_write ON public.leads
  FOR ALL TO authenticated
  USING (public.current_user_has_role('admin'))
  WITH CHECK (public.current_user_has_role('admin'));
CREATE POLICY lead_telecaller_update ON public.leads
  FOR UPDATE TO authenticated
  USING (
    public.current_user_has_permission('lead.qualify')
    AND public.current_user_has_property_assignment(property_id)
  )
  WITH CHECK (
    public.current_user_has_permission('lead.qualify')
    AND public.current_user_has_property_assignment(property_id)
  );
CREATE POLICY lead_history_read ON public.lead_status_history
  FOR SELECT TO authenticated
  USING (public.current_user_can_read_lead_id(lead_id));
CREATE POLICY follow_up_read ON public.lead_follow_ups
  FOR SELECT TO authenticated
  USING (public.current_user_can_read_lead_id(lead_id));
CREATE POLICY follow_up_manage ON public.lead_follow_ups
  FOR ALL TO authenticated
  USING (
    public.current_user_has_role('admin')
    OR (public.current_user_has_permission('lead.qualify') AND public.current_user_can_read_lead_id(lead_id))
  )
  WITH CHECK (
    public.current_user_has_role('admin')
    OR (public.current_user_has_permission('lead.qualify') AND public.current_user_can_read_lead_id(lead_id))
  );

CREATE POLICY user_profile_read ON public.user_profiles
  FOR SELECT TO authenticated
  USING (auth_user_id = auth.uid() OR public.current_user_has_role('admin'));
CREATE POLICY user_profile_admin_write ON public.user_profiles
  FOR ALL TO authenticated
  USING (public.current_user_has_role('admin'))
  WITH CHECK (public.current_user_has_role('admin'));
CREATE POLICY role_assignment_read ON public.user_role_assignments
  FOR SELECT TO authenticated
  USING (auth_user_id = auth.uid() OR public.current_user_has_role('admin'));
CREATE POLICY role_assignment_admin_write ON public.user_role_assignments
  FOR ALL TO authenticated
  USING (public.current_user_has_role('admin'))
  WITH CHECK (public.current_user_has_role('admin'));
CREATE POLICY project_assignment_read ON public.project_assignments
  FOR SELECT TO authenticated
  USING (auth_user_id = auth.uid() OR public.current_user_has_role('admin'));
CREATE POLICY project_assignment_admin_write ON public.project_assignments
  FOR ALL TO authenticated
  USING (public.current_user_has_role('admin'))
  WITH CHECK (public.current_user_has_role('admin'));
CREATE POLICY property_assignment_read ON public.property_assignments
  FOR SELECT TO authenticated
  USING (auth_user_id = auth.uid() OR public.current_user_has_role('admin'));
CREATE POLICY property_assignment_admin_write ON public.property_assignments
  FOR ALL TO authenticated
  USING (public.current_user_has_role('admin'))
  WITH CHECK (public.current_user_has_role('admin'));

CREATE VIEW public.third_party_property_projection
WITH (security_barrier = true)
AS
SELECT
  property.id,
  property.property_type_code,
  property.display_name,
  property.geographic_area_id,
  property.development_project_id,
  property.development_phase_id
FROM public.properties AS property
WHERE public.current_user_has_role('third_party')
  AND public.current_user_has_permission('inventory.read')
  AND public.current_user_has_property_assignment(property.id);

CREATE VIEW public.property_inventory_projection
WITH (security_barrier = true)
AS
SELECT
  property.id,
  property.property_type_code,
  property.display_name,
  property.normalized_name,
  property.geographic_area_id,
  property.development_project_id,
  property.development_phase_id,
  property.parent_property_id,
  property.created_at,
  property.updated_at
FROM public.properties AS property
WHERE public.current_user_has_permission('inventory.read')
  AND NOT public.current_user_has_role('third_party')
  AND (
    public.current_user_has_role('admin')
    OR public.current_user_has_property_assignment(property.id)
  );

DROP VIEW public.property_rera_registrations;
CREATE VIEW public.property_rera_registrations
WITH (security_barrier = true)
AS
SELECT
  property.id AS property_id,
  registration.id AS rera_registration_id,
  registration.registration_number_raw,
  match.development_project_id,
  match.development_phase_id,
  observation.project_name_as_recorded,
  observation.promoter_name_as_recorded,
  observation.status_as_recorded,
  observation.registered_on,
  observation.valid_until,
  observation.observed_at
FROM public.properties AS property
JOIN public.rera_project_matches AS match
  ON match.development_project_id = property.development_project_id
 AND (match.development_phase_id IS NULL OR match.development_phase_id = property.development_phase_id)
 AND match.match_status = 'accepted'
JOIN public.rera_registrations AS registration
  ON registration.id = match.rera_registration_id
LEFT JOIN LATERAL (
  SELECT rera_observation.*
  FROM public.rera_registration_observations AS rera_observation
  WHERE rera_observation.rera_registration_id = registration.id
  ORDER BY rera_observation.observed_at DESC, rera_observation.id DESC
  LIMIT 1
) AS observation ON true
WHERE public.current_user_has_permission('inventory.read')
  AND (
    public.current_user_has_role('admin')
    OR public.current_user_has_property_assignment(property.id)
  );

REVOKE ALL ON FUNCTION public.current_user_has_role(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.current_user_has_permission(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.current_user_has_project_assignment(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.current_user_has_property_assignment(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.current_user_can_read_lead(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.current_user_can_read_lead_id(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.current_user_can_read_contact(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.current_user_has_role(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_user_has_permission(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_user_has_project_assignment(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_user_has_property_assignment(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_user_can_read_lead(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_user_can_read_lead_id(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_user_can_read_contact(uuid) TO authenticated;

GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO authenticated;
REVOKE SELECT ON public.properties FROM authenticated;
GRANT INSERT, UPDATE, DELETE ON
  public.properties,
  public.development_projects,
  public.development_phases,
  public.property_listings,
  public.import_runs,
  public.source_observations,
  public.source_observation_sightings,
  public.registration_documents,
  public.registration_document_observations,
  public.registration_schedules,
  public.registration_schedule_observations,
  public.parties,
  public.party_aliases,
  public.registration_document_parties,
  public.registration_document_relations,
  public.rera_registrations,
  public.rera_registration_observations,
  public.rera_project_matches,
  public.crm_contacts,
  public.crm_contact_methods,
  public.leads,
  public.lead_follow_ups,
  public.user_profiles,
  public.user_role_assignments,
  public.project_assignments,
  public.property_assignments
TO authenticated;
REVOKE INSERT ON public.mobile_captures FROM authenticated;
GRANT INSERT (property_id, phone_as_captured, normalized_phone, capture_source)
  ON public.mobile_captures TO authenticated;
GRANT SELECT ON public.third_party_property_projection TO authenticated;
GRANT SELECT ON public.property_inventory_projection TO authenticated;
GRANT SELECT ON public.property_rera_registrations TO authenticated;