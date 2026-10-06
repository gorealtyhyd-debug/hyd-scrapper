import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createTestDatabase } from './test-database.mjs';

test('canonical identities support projects, units, villas, plots, and unknown types', async () => {
  const database = await createTestDatabase();

  try {
    await database.exec(`
      INSERT INTO public.geographic_areas (id, area_type, source_name, normalized_name)
      VALUES ('00000000-0000-0000-0000-000000000001', 'village', 'Nallagandla', 'nallagandla');
      INSERT INTO public.development_projects
        (id, project_type, display_name, normalized_name, geographic_area_id)
      VALUES
        ('00000000-0000-0000-0000-000000000010', 'apartment_community', 'Sarovar Zicon', 'sarovar zicon', '00000000-0000-0000-0000-000000000001');
      INSERT INTO public.development_phases
        (id, development_project_id, display_name, normalized_name)
      VALUES
        ('00000000-0000-0000-0000-000000000020', '00000000-0000-0000-0000-000000000010', 'F Block', 'f block');
      INSERT INTO public.properties
        (id, property_type_code, display_name, normalized_name, geographic_area_id, development_project_id, development_phase_id)
      VALUES
        ('00000000-0000-0000-0000-000000000030', 'apartment_flat', 'Flat 2102', 'flat 2102', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000010', '00000000-0000-0000-0000-000000000020'),
        ('00000000-0000-0000-0000-000000000031', 'villa', 'Villa 2', 'villa 2', '00000000-0000-0000-0000-000000000001', NULL, NULL),
        ('00000000-0000-0000-0000-000000000032', 'open_plot', 'Plot 38', 'plot 38', '00000000-0000-0000-0000-000000000001', NULL, NULL),
        ('00000000-0000-0000-0000-000000000033', 'unknown', 'Unclassified property', 'unclassified property', '00000000-0000-0000-0000-000000000001', NULL, NULL);
      INSERT INTO public.residential_unit_details (property_id, unit_number, built_area_sqft)
      VALUES ('00000000-0000-0000-0000-000000000030', '2102', 1825);
      INSERT INTO public.land_plot_details (property_id, plot_number, extent_sqyd)
      VALUES ('00000000-0000-0000-0000-000000000032', '38', 320);
      INSERT INTO public.property_identifiers
        (property_id, identifier_type, raw_value, normalized_value, development_project_id, development_phase_id)
      VALUES
        ('00000000-0000-0000-0000-000000000030', 'flat_number', '2102', '2102', '00000000-0000-0000-0000-000000000010', '00000000-0000-0000-0000-000000000020');
    `);

    const count = await database.query(
      'SELECT count(*)::integer AS count FROM public.properties',
    );
    assert.equal(count.rows[0].count, 4);

    await assert.rejects(
      database.query(`
        INSERT INTO public.property_identifiers
          (property_id, identifier_type, raw_value, normalized_value, development_project_id, development_phase_id)
        VALUES
          ('00000000-0000-0000-0000-000000000030', 'flat_number', '2102', '2102', '00000000-0000-0000-0000-000000000010', '00000000-0000-0000-0000-000000000020');
      `),
    );

    await assert.rejects(
      database.query(`
        INSERT INTO public.properties
          (property_type_code, display_name, normalized_name, development_project_id, development_phase_id)
        VALUES
          ('apartment_flat', 'Invalid phase link', 'invalid', '00000000-0000-0000-0000-000000000099', '00000000-0000-0000-0000-000000000020');
      `),
    );
  } finally {
    await database.close();
  }
});