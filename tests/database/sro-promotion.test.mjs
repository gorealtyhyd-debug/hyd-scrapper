import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createTestDatabase } from './test-database.mjs';
import { importSroRows } from '../../ingestion/sro-importer.mjs';
import { promoteSroObservations } from '../../ingestion/sro-promoter.mjs';

const rows = [
  {
    sro_code: '1522',
    sro_name: 'Serilingampally',
    registration_year: '2026',
    book_no: '1',
    document_no: '10',
    schedule_no: '1',
    document_description: 'SALE DEED',
    registration_date: '(R) 01-01-2026',
    market_value: 'Mkt.Value:Rs. 774900',
    consideration_value: 'Cons.Value:Rs. 8150000',
    property_details: 'APARTMENT: PROJECT A FLAT: 2102',
  },
  {
    sro_code: '1522',
    sro_name: 'Serilingampally',
    registration_year: '2026',
    book_no: '1',
    document_no: '10',
    schedule_no: '2',
    document_description: 'SALE DEED',
    registration_date: '(R) 01-01-2026',
    property_details: 'PLOT: 38 SURVEY: 64',
  },
  {
    sro_code: '1522',
    sro_name: 'Serilingampally',
    registration_year: '2026',
    book_no: '1',
    document_no: '11',
    schedule_no: '1',
    document_description: 'UNLISTED INSTRUMENT TYPE',
    registration_date: '(R) 02-01-2026',
    property_details: 'HOUSE: 12-4-32',
  },
];

test('SRO source schedules promote to one document with versioned schedule history', async () => {
  const database = await createTestDatabase();

  try {
    await importSroRows(database, rows, {
      runKind: 'historical_backfill',
      parserVersion: '1.0.0',
    });
    const observationRows = await database.query(
      'SELECT id FROM public.source_observations ORDER BY source_record_key',
    );
    const observationIds = observationRows.rows.map((row) => row.id);

    const firstPromotion = await promoteSroObservations(database, observationIds);
    const replayPromotion = await promoteSroObservations(database, observationIds);
    assert.equal(firstPromotion.promotedCount, 3);
    assert.equal(replayPromotion.promotedCount, 3);

    const counts = await database.query(`
      SELECT
        (SELECT count(*)::integer FROM public.registration_documents) AS documents,
        (SELECT count(*)::integer FROM public.registration_schedules) AS schedules,
        (SELECT count(*)::integer FROM public.registration_document_observations) AS document_observations,
        (SELECT count(*)::integer FROM public.registration_schedule_observations) AS schedule_observations
    `);
    assert.deepEqual(counts.rows[0], {
      documents: 2,
      schedules: 3,
      document_observations: 3,
      schedule_observations: 3,
    });

    const document = await database.query(
      `SELECT document_no, document_type_code, document_type_as_recorded, consideration_value
       FROM public.registration_documents ORDER BY document_no`,
    );
    assert.equal(document.rows[0].document_type_code, 'sale_deed');
    assert.equal(document.rows[0].document_type_as_recorded, 'SALE DEED');
    assert.equal(document.rows[0].consideration_value, '8150000.00');
    assert.equal(document.rows[1].document_type_code, 'other');
    assert.equal(document.rows[1].document_type_as_recorded, 'UNLISTED INSTRUMENT TYPE');

    await database.exec(`
      INSERT INTO public.properties (id, property_type_code, display_name, normalized_name)
      VALUES
        ('00000000-0000-0000-0000-000000000021', 'apartment_flat', 'Flat 2102', 'flat 2102'),
        ('00000000-0000-0000-0000-000000000022', 'open_plot', 'Plot 38', 'plot 38');
    `);
    const schedules = await database.query(`
      SELECT s.schedule_number, so.id AS observation_id
      FROM public.registration_documents AS d
      JOIN public.registration_schedules AS s ON s.registration_document_id = d.id
      JOIN public.registration_schedule_observations AS so ON so.registration_schedule_id = s.id
      WHERE d.document_no = '10'
      ORDER BY s.schedule_number
    `);
    const firstSchedule = schedules.rows[0].observation_id;
    const secondSchedule = schedules.rows[1].observation_id;

    await database.query(
      `INSERT INTO public.registration_schedule_property_matches
        (registration_schedule_observation_id, property_id, match_method, match_status, confidence, source_reference)
       VALUES
        ($1, '00000000-0000-0000-0000-000000000021', 'normalized_text', 'pending', 0.7200, 'match-a'),
        ($1, '00000000-0000-0000-0000-000000000022', 'manual_review', 'accepted', 1.0000, 'review-a'),
        ($2, '00000000-0000-0000-0000-000000000022', 'normalized_text', 'pending', 0.6300, 'match-b')`,
      [firstSchedule, secondSchedule],
    );

    const matches = await database.query(
      `SELECT match_status, count(*)::integer AS count
       FROM public.registration_schedule_property_matches
       GROUP BY match_status ORDER BY match_status`,
    );
    assert.deepEqual(matches.rows, [
      { match_status: 'accepted', count: 1 },
      { match_status: 'pending', count: 2 },
    ]);

    await assert.rejects(
      database.query(`
        INSERT INTO public.registration_schedule_property_matches
          (registration_schedule_observation_id, property_id, match_method, match_status, confidence)
        VALUES ($1, '00000000-0000-0000-0000-000000000021', 'manual_review', 'accepted', 1.2)
      `, [firstSchedule]),
    );
  } finally {
    await database.close();
  }
});