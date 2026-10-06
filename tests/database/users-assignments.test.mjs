import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createTestDatabase } from './test-database.mjs';

test('user roles and property/project assignments enforce unique valid relationships', async () => {
  const database = await createTestDatabase();

  try {
    await database.exec(`
      INSERT INTO auth.users (id)
      VALUES
        ('00000000-0000-0000-0000-000000000001'),
        ('00000000-0000-0000-0000-000000000002');
      INSERT INTO public.user_profiles (auth_user_id, display_name)
      VALUES
        ('00000000-0000-0000-0000-000000000001', 'Admin User'),
        ('00000000-0000-0000-0000-000000000002', 'Sales User');
      INSERT INTO public.development_projects
        (id, project_type, display_name, normalized_name)
      VALUES ('00000000-0000-0000-0000-000000000010', 'villa_community', 'Project A', 'project a');
      INSERT INTO public.properties
        (id, property_type_code, display_name, normalized_name, development_project_id)
      VALUES ('00000000-0000-0000-0000-000000000011', 'villa', 'Villa 1', 'villa 1', '00000000-0000-0000-0000-000000000010');
      INSERT INTO public.user_role_assignments (auth_user_id, role_code, assigned_by)
      VALUES ('00000000-0000-0000-0000-000000000002', 'sales_representative', '00000000-0000-0000-0000-000000000001');
      INSERT INTO public.project_assignments (auth_user_id, development_project_id, assigned_by)
      VALUES ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000010', '00000000-0000-0000-0000-000000000001');
      INSERT INTO public.property_assignments (auth_user_id, property_id, assigned_by)
      VALUES ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000001');
    `);

    const permissions = await database.query(
      `SELECT permission_code FROM public.role_permissions
       WHERE role_code = 'sales_representative' ORDER BY permission_code`,
    );
    assert.deepEqual(permissions.rows.map((row) => row.permission_code), [
      'inventory.read',
      'lead.read',
      'listing.read',
      'sales.manage',
    ]);

    await assert.rejects(
      database.query(`
        INSERT INTO public.user_role_assignments (auth_user_id, role_code)
        VALUES ('00000000-0000-0000-0000-000000000002', 'sales_representative');
      `),
    );
    await assert.rejects(
      database.query(`
        INSERT INTO public.property_assignments (auth_user_id, property_id)
        VALUES ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000099');
      `),
    );
  } finally {
    await database.close();
  }
});