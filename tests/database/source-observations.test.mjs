import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createTestDatabase } from './test-database.mjs';

test('source versions are idempotent while repeated retrievals remain traceable', async () => {
  const database = await createTestDatabase();

  try {
    await database.exec(`
      INSERT INTO public.registration_offices (id, source_system_code, sro_code, name)
      VALUES ('00000000-0000-0000-0000-000000000001', 'telangana_sro', '1522', 'Serilingampally');
      INSERT INTO public.import_runs (id, source_system_code, registration_office_id, run_kind)
      VALUES
        ('00000000-0000-0000-0000-000000000002', 'telangana_sro', '00000000-0000-0000-0000-000000000001', 'historical_backfill'),
        ('00000000-0000-0000-0000-000000000003', 'telangana_sro', '00000000-0000-0000-0000-000000000001', 'replay');
    `);

    const inserted = await database.query(
      `INSERT INTO public.source_observations
        (source_system_code, registration_office_id, source_record_type, source_record_key,
         content_hash, raw_payload, parser_version)
       VALUES ($1, $2, $3, $4, $5, $6::jsonb, $7)
       ON CONFLICT (source_system_code, registration_office_id, source_record_type, source_record_key, content_hash)
       DO NOTHING
       RETURNING id`,
      [
        'telangana_sro',
        '00000000-0000-0000-0000-000000000001',
        'sro_schedule',
        '1522:2026:1:1:1',
        'a'.repeat(64),
        JSON.stringify({ document_no: '1', schedule_no: '1' }),
        '1.0.0',
      ],
    );

    const replay = await database.query(
      `INSERT INTO public.source_observations
        (source_system_code, registration_office_id, source_record_type, source_record_key,
         content_hash, raw_payload, parser_version)
       VALUES ($1, $2, $3, $4, $5, $6::jsonb, $7)
       ON CONFLICT (source_system_code, registration_office_id, source_record_type, source_record_key, content_hash)
       DO NOTHING
       RETURNING id`,
      [
        'telangana_sro',
        '00000000-0000-0000-0000-000000000001',
        'sro_schedule',
        '1522:2026:1:1:1',
        'a'.repeat(64),
        JSON.stringify({ document_no: '1', schedule_no: '1' }),
        '1.0.0',
      ],
    );

    assert.equal(inserted.rows.length, 1);
    assert.equal(replay.rows.length, 0);
    const observation = inserted.rows[0].id;

    await database.query(
      `INSERT INTO public.source_observation_sightings (source_observation_id, import_run_id)
       VALUES ($1, $2), ($1, $3)`,
      [observation, '00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000003'],
    );

    const count = await database.query(
      `SELECT
         (SELECT count(*)::integer FROM public.source_observations) AS observations,
         (SELECT count(*)::integer FROM public.source_observation_sightings) AS sightings`,
    );
    assert.equal(count.rows[0].observations, 1);
    assert.equal(count.rows[0].sightings, 2);
  } finally {
    await database.close();
  }
});