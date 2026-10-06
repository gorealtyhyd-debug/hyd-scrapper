import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createTestDatabase } from './test-database.mjs';

test('RERA identifiers are separate from SRO documents and preserve status observations', async () => {
  const database = await createTestDatabase();

  try {
    await database.exec(`
      INSERT INTO public.source_observations
        (id, source_system_code, source_record_type, source_record_key, content_hash, raw_payload, parser_version)
      VALUES
        ('00000000-0000-0000-0000-000000000001', 'telangana_rera', 'rera_project', 'TS123', repeat('a', 64), '{"status":"Active"}', '1.0.0'),
        ('00000000-0000-0000-0000-000000000002', 'telangana_rera', 'rera_project', 'TS123', repeat('b', 64), '{"status":"Expired"}', '1.0.0');
      INSERT INTO public.rera_registrations
        (id, source_system_code, registration_number_raw, normalized_registration_number)
      VALUES ('00000000-0000-0000-0000-000000000003', 'telangana_rera', 'P02400001234', 'P02400001234');
      INSERT INTO public.rera_registration_observations
        (rera_registration_id, source_observation_id, project_name_as_recorded,
         promoter_name_as_recorded, status_as_recorded, registered_on, valid_until)
      VALUES
        ('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001', 'Project A', 'Promoter A', 'Active', '2022-01-01', '2027-01-01'),
        ('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000002', 'Project A', 'Promoter A', 'Expired', '2022-01-01', '2027-01-01');
      INSERT INTO public.registration_offices (id, source_system_code, sro_code, name)
      VALUES ('00000000-0000-0000-0000-000000000004', 'telangana_sro', '1522', 'Office A');
      INSERT INTO public.registration_documents
        (source_system_code, registration_office_id, registration_year, document_no)
      VALUES ('telangana_sro', '00000000-0000-0000-0000-000000000004', 2026, '1234');
    `);

    const history = await database.query(
      `SELECT status_as_recorded
       FROM public.rera_registration_observations
       WHERE rera_registration_id = $1
      ORDER BY observed_at, observation_sequence`,
      ['00000000-0000-0000-0000-000000000003'],
    );
    assert.deepEqual(history.rows.map((row) => row.status_as_recorded), ['Active', 'Expired']);

    const count = await database.query(
      `SELECT count(*)::integer AS count FROM public.registration_documents`,
    );
    assert.equal(count.rows[0].count, 1);

    await assert.rejects(
      database.query(`
        INSERT INTO public.rera_registrations
          (source_system_code, registration_number_raw, normalized_registration_number)
        VALUES ('telangana_rera', 'P02400001234', 'P02400001234');
      `),
    );
  } finally {
    await database.close();
  }
});