import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createTestDatabase } from './test-database.mjs';

test('only reviewed RERA project or phase matches flow to properties', async () => {
  const database = await createTestDatabase();

  try {
    await database.exec(`
      INSERT INTO auth.users (id)
      VALUES ('00000000-0000-0000-0000-000000000099');
      INSERT INTO public.user_profiles (auth_user_id, display_name)
      VALUES ('00000000-0000-0000-0000-000000000099', 'Assigned Sales');
      INSERT INTO public.user_role_assignments (auth_user_id, role_code)
      VALUES ('00000000-0000-0000-0000-000000000099', 'sales_representative');
      INSERT INTO public.development_projects
        (id, project_type, display_name, normalized_name)
      VALUES
        ('00000000-0000-0000-0000-000000000001', 'apartment_community', 'Project A', 'project a'),
        ('00000000-0000-0000-0000-000000000002', 'plotted_development', 'Project B', 'project b');
      INSERT INTO public.development_phases
        (id, development_project_id, display_name, normalized_name)
      VALUES ('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001', 'Phase 1', 'phase 1');
      INSERT INTO public.properties
        (id, property_type_code, display_name, normalized_name, development_project_id, development_phase_id)
      VALUES ('00000000-0000-0000-0000-000000000004', 'apartment_flat', 'Flat 1201', 'flat 1201', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000003');
      INSERT INTO public.rera_registrations
        (id, source_system_code, registration_number_raw, normalized_registration_number)
      VALUES
        ('00000000-0000-0000-0000-000000000011', 'telangana_rera', 'RERA-A', 'RERA-A'),
        ('00000000-0000-0000-0000-000000000012', 'telangana_rera', 'RERA-B', 'RERA-B');
      INSERT INTO public.source_observations
        (id, source_system_code, source_record_type, source_record_key, content_hash, raw_payload, parser_version)
      VALUES
        ('00000000-0000-0000-0000-000000000021', 'telangana_rera', 'rera_project', 'RERA-A', repeat('a', 64), '{"status":"Active"}', '1'),
        ('00000000-0000-0000-0000-000000000022', 'telangana_rera', 'rera_project', 'RERA-B', repeat('b', 64), '{"status":null}', '1');
      INSERT INTO public.rera_registration_observations
        (rera_registration_id, source_observation_id, project_name_as_recorded, status_as_recorded)
      VALUES
        ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000021', 'Project A Phase 1', 'Active'),
        ('00000000-0000-0000-0000-000000000012', '00000000-0000-0000-0000-000000000022', 'Project B', NULL);
      INSERT INTO public.rera_project_matches
        (rera_registration_id, development_project_id, development_phase_id, match_method, match_status, confidence, source_reference)
      VALUES
        ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000001', NULL, 'name_location', 'pending', 0.7000, 'candidate-a'),
        ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000003', 'manual_review', 'accepted', 1.0000, 'review-a'),
        ('00000000-0000-0000-0000-000000000012', '00000000-0000-0000-0000-000000000002', NULL, 'name_location', 'pending', 0.5500, 'candidate-b');
    `);

    await database.query(
      `INSERT INTO public.project_assignments (auth_user_id, development_project_id)
       VALUES ('00000000-0000-0000-0000-000000000099', '00000000-0000-0000-0000-000000000001')`,
    );

    await database.query(
      "SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000099', false)",
    );
    await database.query('SET ROLE authenticated');
    const visible = await database.query(
      `SELECT registration_number_raw, status_as_recorded, development_phase_id
       FROM public.property_rera_registrations
       WHERE property_id = $1`,
      ['00000000-0000-0000-0000-000000000004'],
    );
    assert.deepEqual(visible.rows, [{
      registration_number_raw: 'RERA-A',
      status_as_recorded: 'Active',
      development_phase_id: '00000000-0000-0000-0000-000000000003',
    }]);

    await database.query('RESET ROLE');

    await assert.rejects(
      database.query(`
        INSERT INTO public.rera_project_matches
          (rera_registration_id, development_project_id, match_method, match_status, confidence, source_reference)
        VALUES ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000002', 'manual_review', 'accepted', 1, 'conflicting-review');
      `),
    );
  } finally {
    await database.close();
  }
});