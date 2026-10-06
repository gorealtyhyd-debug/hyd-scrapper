import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createTestDatabase } from './test-database.mjs';

const thirdPartyUser = '00000000-0000-0000-0000-000000000001';
const salesUser = '00000000-0000-0000-0000-000000000002';
const adminUser = '00000000-0000-0000-0000-000000000003';
const assignedProperty = '00000000-0000-0000-0000-000000000011';
const unassignedProperty = '00000000-0000-0000-0000-000000000012';

async function assumeAuthenticatedUser(database, authUserId) {
  await database.query(
    "SELECT set_config('request.jwt.claim.sub', $1, false)",
    [authUserId],
  );
  await database.query('SET ROLE authenticated');
}

test('RLS enforces assignments, qualified lead visibility, and third-party limits', async () => {
  const database = await createTestDatabase();

  try {
    await database.exec(`
      INSERT INTO auth.users (id) VALUES
        ('${thirdPartyUser}'), ('${salesUser}'), ('${adminUser}');
      INSERT INTO public.user_profiles (auth_user_id, display_name) VALUES
        ('${thirdPartyUser}', 'Third Party'),
        ('${salesUser}', 'Sales Representative'),
        ('${adminUser}', 'Administrator');
      INSERT INTO public.user_role_assignments (auth_user_id, role_code) VALUES
        ('${thirdPartyUser}', 'third_party'),
        ('${salesUser}', 'sales_representative'),
        ('${adminUser}', 'admin');
      INSERT INTO public.development_projects (id, project_type, display_name, normalized_name) VALUES
        ('00000000-0000-0000-0000-000000000021', 'villa_community', 'Project A', 'project a'),
        ('00000000-0000-0000-0000-000000000022', 'apartment_community', 'Project B', 'project b');
      INSERT INTO public.properties
        (id, property_type_code, display_name, normalized_name, development_project_id)
      VALUES
        ('${assignedProperty}', 'villa', 'Villa 1', 'villa 1', '00000000-0000-0000-0000-000000000021'),
        ('${unassignedProperty}', 'apartment_flat', 'Flat 101', 'flat 101', '00000000-0000-0000-0000-000000000022');
      INSERT INTO public.residential_unit_details (property_id, unit_number, built_area_sqft)
      VALUES ('${assignedProperty}', '1', 2100);
      INSERT INTO public.property_assignments (auth_user_id, property_id)
      VALUES ('${thirdPartyUser}', '${assignedProperty}');
      INSERT INTO public.project_assignments (auth_user_id, development_project_id)
      VALUES ('${salesUser}', '00000000-0000-0000-0000-000000000021');
      INSERT INTO public.leads (property_id, lead_status_code) VALUES
        ('${assignedProperty}', 'pending'),
        ('${assignedProperty}', 'resale'),
        ('${unassignedProperty}', 'resale');
      INSERT INTO public.source_observations
        (source_system_code, source_record_type, source_record_key, content_hash, raw_payload, parser_version)
      VALUES ('telangana_sro', 'sro_schedule', 'raw-1', repeat('a', 64), '{"party_names":"private"}', '1');
    `);

    await assumeAuthenticatedUser(database, thirdPartyUser);
    await assert.rejects(
      database.query('SELECT id FROM public.properties'),
      /permission denied for table properties/,
    );

    const safeProjection = await database.query(
      'SELECT * FROM public.third_party_property_projection',
    );
    assert.equal(safeProjection.rows.length, 1);
    assert.equal(safeProjection.rows[0].display_name, 'Villa 1');
    assert.equal('built_area_sqft' in safeProjection.rows[0], false);

    const privateSource = await database.query(
      'SELECT id FROM public.source_observations',
    );
    assert.equal(privateSource.rows.length, 0);
    const internalDetails = await database.query(
      'SELECT property_id FROM public.residential_unit_details',
    );
    assert.equal(internalDetails.rows.length, 0);

    await database.query(
      `INSERT INTO public.mobile_captures
        (property_id, phone_as_captured, normalized_phone, capture_source)
       VALUES ($1, '9000000000', '+919000000000', 'third_party')`,
      [assignedProperty],
    );
    await assert.rejects(
      database.query(
        `INSERT INTO public.mobile_captures
          (property_id, phone_as_captured, normalized_phone, capture_source)
         VALUES ($1, '9000000001', '+919000000001', 'third_party')`,
        [unassignedProperty],
      ),
    );
    await database.query('RESET ROLE');

    const captured = await database.query(
      'SELECT captured_by FROM public.mobile_captures WHERE property_id = $1',
      [assignedProperty],
    );
    assert.equal(captured.rows[0].captured_by, thirdPartyUser);

    await assumeAuthenticatedUser(database, salesUser);
    const salesLeads = await database.query(
      'SELECT lead_status_code FROM public.leads ORDER BY lead_status_code',
    );
    assert.deepEqual(salesLeads.rows, [{ lead_status_code: 'resale' }]);
    await database.query('RESET ROLE');

    await assumeAuthenticatedUser(database, adminUser);
    const adminProperties = await database.query(
      'SELECT count(*)::integer AS count FROM public.property_inventory_projection',
    );
    const adminSources = await database.query(
      'SELECT count(*)::integer AS count FROM public.source_observations',
    );
    assert.equal(adminProperties.rows[0].count, 2);
    assert.equal(adminSources.rows[0].count, 1);
    await database.query(
      `INSERT INTO public.mobile_captures
        (property_id, phone_as_captured, normalized_phone, capture_source)
       VALUES ($1, '9000000002', '+919000000002', 'admin')`,
      [unassignedProperty],
    );
    await database.query('RESET ROLE');

    const adminCapture = await database.query(
      'SELECT captured_by FROM public.mobile_captures WHERE normalized_phone = $1',
      ['+919000000002'],
    );
    assert.equal(adminCapture.rows[0].captured_by, adminUser);
  } finally {
    await database.close();
  }
});