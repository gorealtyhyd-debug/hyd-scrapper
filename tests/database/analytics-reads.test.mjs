import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createTestDatabase } from './test-database.mjs';
import { ingestAndPromoteSroRows } from '../../ingestion/sro-pipeline.mjs';

const records = [
  { document_no: '10', document_description: 'SALE DEED', registration_date: '(R) 01-01-2026', market_value: 'Mkt.Value:Rs. 774900', consideration_value: 'Cons.Value:Rs. 8150000' },
  { document_no: '11', document_description: 'MORTGAGE WITHOUT POSSESSION', registration_date: '(R) 02-02-2026', market_value: 'Mkt.Value:Rs. 1649200', consideration_value: 'Cons.Value:Rs. 5824000' },
  { document_no: '12', document_description: 'RECTIFICATION DEED', registration_date: '(R) 03-03-2026', market_value: 'Mkt.Value:Rs. 100', consideration_value: 'Cons.Value:Rs. 1' },
  { document_no: '13', document_description: 'SALE DEED', registration_date: '(R) 05-02-2026', market_value: 'Mkt.Value:Rs. 2980800', consideration_value: 'Cons.Value:Rs. 9500000' },
].map((record) => ({
  sro_code: '1522',
  sro_name: 'Serilingampally',
  registration_year: '2026',
  book_no: '1',
  schedule_no: '1',
  property_details: `FLAT: ${record.document_no}01`,
  ...record,
}));

test('sale trends classify only sale deeds and source coverage reports ingestion span', async () => {
  const database = await createTestDatabase();

  try {
    await ingestAndPromoteSroRows(database, records, {
      runKind: 'historical_backfill',
      parserVersion: '1.0.0',
    });
    await database.exec(`
      INSERT INTO auth.users (id) VALUES ('00000000-0000-0000-0000-000000000099');
      INSERT INTO public.user_profiles (auth_user_id, display_name)
      VALUES ('00000000-0000-0000-0000-000000000099', 'Analytics Admin');
      SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000099', false);
      INSERT INTO public.user_role_assignments (auth_user_id, role_code)
      VALUES ('00000000-0000-0000-0000-000000000099', 'admin');
      INSERT INTO public.properties (id, property_type_code, display_name, normalized_name)
      VALUES ('00000000-0000-0000-0000-000000000001', 'apartment_flat', 'Flat 1001', 'flat 1001');
    `);

    const scheduleObservations = await database.query(`
      SELECT observation.id
      FROM public.registration_schedule_observations AS observation
      JOIN public.registration_schedules AS schedule ON schedule.id = observation.registration_schedule_id
      JOIN public.registration_documents AS document ON document.id = schedule.registration_document_id
      ORDER BY document.document_no
    `);
    for (const observation of scheduleObservations.rows) {
      await database.query(
        `INSERT INTO public.registration_schedule_property_matches
          (registration_schedule_observation_id, property_id, match_method, match_status, confidence, source_reference)
         VALUES ($1, '00000000-0000-0000-0000-000000000001', 'manual_review', 'accepted', 1, $2)`,
        [observation.id, `review-${observation.id}`],
      );
    }

    await database.query('SET ROLE authenticated');
    const trends = await database.query(
            `SELECT to_char(registration_month, 'YYYY-MM-DD') AS registration_month,
              sale_event_count, consideration_value_count,
              average_recorded_consideration, included_document_type_codes
       FROM public.property_sale_trends_monthly
       ORDER BY registration_month`,
    );
    assert.deepEqual(trends.rows, [
      {
        registration_month: '2026-01-01',
        sale_event_count: 1,
        consideration_value_count: 1,
        average_recorded_consideration: '8150000.000000000000',
        included_document_type_codes: ['sale_deed'],
      },
      {
        registration_month: '2026-02-01',
        sale_event_count: 1,
        consideration_value_count: 1,
        average_recorded_consideration: '9500000.000000000000',
        included_document_type_codes: ['sale_deed'],
      },
    ]);

    const coverage = await database.query(
      `SELECT source_observation_count, promoted_observation_count, invalid_observation_count,
              registration_document_count,
              to_char(first_registration_date, 'YYYY-MM-DD') AS first_registration_date,
              to_char(last_registration_date, 'YYYY-MM-DD') AS last_registration_date
       FROM public.source_coverage_by_sro WHERE sro_code = '1522'`,
    );
    assert.deepEqual(coverage.rows[0], {
      source_observation_count: 4,
      promoted_observation_count: 4,
      invalid_observation_count: 0,
      registration_document_count: 4,
      first_registration_date: '2026-01-01',
      last_registration_date: '2026-03-03',
    });
    await database.query('RESET ROLE');
  } finally {
    await database.close();
  }
});