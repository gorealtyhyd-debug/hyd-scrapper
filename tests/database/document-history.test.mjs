import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createTestDatabase } from './test-database.mjs';
import { ingestAndPromoteSroRows } from '../../ingestion/sro-pipeline.mjs';

const rows = [
  { document_no: '10', document_description: 'SALE DEED', registration_date: '(R) 01-01-2026', consideration_value: 'Cons.Value:Rs. 8150000' },
  { document_no: '11', document_description: 'MORTGAGE WITHOUT POSSESSION', registration_date: '(R) 02-01-2026', consideration_value: 'Cons.Value:Rs. 5824000' },
  { document_no: '12', document_description: 'RECTIFICATION DEED', registration_date: '(R) 03-01-2026', consideration_value: 'Cons.Value:Rs. 1' },
  { document_no: '13', document_description: 'SALE DEED', registration_date: '(R) 04-01-2026', consideration_value: 'Cons.Value:Rs. 9500000' },
].map((row) => ({
  sro_code: '1522',
  sro_name: 'Serilingampally',
  registration_year: '2026',
  book_no: '1',
  schedule_no: '1',
  property_details: `FLAT: ${row.document_no}02`,
  ...row,
}));

test('property history includes accepted legal events but sale reads exclude non-sales', async () => {
  const database = await createTestDatabase();

  try {
    const importResult = await ingestAndPromoteSroRows(database, rows, {
      runKind: 'historical_backfill',
      parserVersion: '1.0.0',
    });
    assert.equal(importResult.recordCount, 4);
    assert.equal(importResult.promotedCount, 4);

    await database.exec(`
      INSERT INTO public.development_projects
        (id, project_type, display_name, normalized_name)
      VALUES ('00000000-0000-0000-0000-000000000030', 'apartment_community', 'Project A', 'project a');
      INSERT INTO public.development_phases
        (id, development_project_id, display_name, normalized_name)
      VALUES ('00000000-0000-0000-0000-000000000031', '00000000-0000-0000-0000-000000000030', 'Phase 1', 'phase 1');
      INSERT INTO public.properties (id, property_type_code, display_name, normalized_name)
      VALUES ('00000000-0000-0000-0000-000000000001', 'apartment_flat', 'Flat 1002', 'flat 1002');
      UPDATE public.properties
      SET development_project_id = '00000000-0000-0000-0000-000000000030',
          development_phase_id = '00000000-0000-0000-0000-000000000031'
      WHERE id = '00000000-0000-0000-0000-000000000001';
      INSERT INTO public.property_listings
        (property_id, listing_type_code, listing_status_code, asking_price, currency_code, rent_period)
      VALUES
        ('00000000-0000-0000-0000-000000000001', 'sale', 'active', 15000000, 'INR', NULL),
        ('00000000-0000-0000-0000-000000000001', 'rent', 'active', 55000, 'INR', 'month');
    `);
    const schedules = await database.query(`
      SELECT document.document_no, schedule_observation.id
      FROM public.registration_documents AS document
      JOIN public.registration_schedules AS schedule
        ON schedule.registration_document_id = document.id
      JOIN public.registration_schedule_observations AS schedule_observation
        ON schedule_observation.registration_schedule_id = schedule.id
      ORDER BY document.document_no
    `);

    for (const [index, schedule] of schedules.rows.entries()) {
      await database.query(
        `INSERT INTO public.registration_schedule_property_matches
          (registration_schedule_observation_id, property_id, match_method, match_status, confidence)
         VALUES ($1, '00000000-0000-0000-0000-000000000001', 'manual_review', $2, 1.0000)`,
        [schedule.id, index === 3 ? 'pending' : 'accepted'],
      );
    }

    const rectification = await database.query(
      `SELECT id FROM public.registration_documents WHERE document_no = '12'`,
    );
    const sale = await database.query(
      `SELECT id FROM public.registration_documents WHERE document_no = '10'`,
    );
    await database.query(
      `INSERT INTO public.registration_document_relations
        (from_registration_document_id, to_registration_document_id, relation_type, source_reference)
       VALUES ($1, $2, 'rectifies', 'document 12 states rectification of document 10')`,
      [rectification.rows[0].id, sale.rows[0].id],
    );

    await database.exec(`
      INSERT INTO auth.users (id) VALUES ('00000000-0000-0000-0000-000000000099');
      INSERT INTO public.user_profiles (auth_user_id, display_name)
      VALUES ('00000000-0000-0000-0000-000000000099', 'Analytics Admin');
      SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000099', false);
      INSERT INTO public.user_role_assignments (auth_user_id, role_code)
      VALUES ('00000000-0000-0000-0000-000000000099', 'admin');
    `);
    await database.query('SET ROLE authenticated');

    const profile = await database.query(
      `SELECT property_type_label, development_project_name, development_phase_name
       FROM public.property_profile_read WHERE property_id = $1`,
      ['00000000-0000-0000-0000-000000000001'],
    );
    assert.deepEqual(profile.rows, [{
      property_type_label: 'Apartment or flat',
      development_project_name: 'Project A',
      development_phase_name: 'Phase 1',
    }]);

    const currentListings = await database.query(
      `SELECT listing_type_code, asking_price, rent_period
       FROM public.property_current_listings
       WHERE property_id = $1 ORDER BY listing_type_code`,
      ['00000000-0000-0000-0000-000000000001'],
    );
    assert.deepEqual(currentListings.rows, [
      { listing_type_code: 'rent', asking_price: '55000.00', rent_period: 'month' },
      { listing_type_code: 'sale', asking_price: '15000000.00', rent_period: null },
    ]);

    const history = await database.query(
      `SELECT document_no, document_type_code, is_sale_event, source_observation_id
       FROM public.property_registration_history
       WHERE property_id = $1 ORDER BY registration_date`,
      ['00000000-0000-0000-0000-000000000001'],
    );
    assert.deepEqual(
      history.rows.map(({ document_no, document_type_code, is_sale_event }) => ({
        document_no,
        document_type_code,
        is_sale_event,
      })),
      [
        { document_no: '10', document_type_code: 'sale_deed', is_sale_event: true },
        { document_no: '11', document_type_code: 'mortgage_without_possession', is_sale_event: false },
        { document_no: '12', document_type_code: 'rectification', is_sale_event: false },
      ],
    );
    assert.ok(history.rows.every((row) => row.source_observation_id));

    const saleEvents = await database.query(
      `SELECT document_no FROM public.property_sale_events
       WHERE property_id = $1 ORDER BY registration_date`,
      ['00000000-0000-0000-0000-000000000001'],
    );
    assert.deepEqual(saleEvents.rows, [{ document_no: '10' }]);
    await database.query('RESET ROLE');
  } finally {
    await database.close();
  }
});