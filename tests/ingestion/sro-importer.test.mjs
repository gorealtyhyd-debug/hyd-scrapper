import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createTestDatabase } from '../database/test-database.mjs';
import { hashSroPayload, importSroRows, parseSroCsv, parseSroRecord } from '../../ingestion/sro-importer.mjs';

const sourceRows = [
  {
    id: '1',
    sro_code: '1522',
    document_no: '1',
    schedule_no: '1',
    registration_year: '2026',
    book_no: '1',
    sro_name: 'SERILINGAMPALLI',
    property_details: 'APARTMENT: APARNA SAROVAR ZICON FLAT: 2102',
    party_names: '1.(CL)Person One',
    fetched_at: '2026-10-05 14:35:03',
  },
  {
    id: '2',
    sro_code: '1522',
    document_no: '1',
    schedule_no: '2',
    registration_year: '2026',
    book_no: '1',
    sro_name: 'SERILINGAMPALLI',
    property_details: 'PLOT: 38 SURVEY: 64',
    party_names: '1.(EX)Person Two',
    fetched_at: '2026-10-05 14:35:04',
  },
];

test('CSV parsing preserves quoted source text and excludes fetch time from content identity', () => {
  const parsed = parseSroCsv('id,property_details\n1,"FLAT: 2102, BLOCK A"\n');
  assert.equal(parsed[0].property_details, 'FLAT: 2102, BLOCK A');
  assert.equal(
    hashSroPayload(sourceRows[0]),
    hashSroPayload({ ...sourceRows[0], id: '987', fetched_at: '2026-10-06 09:00:00' }),
  );
});

test('source validation reports malformed dates, values, and missing identifiers', () => {
  const valid = parseSroRecord({
    ...sourceRows[0],
    registration_date: '(R) 01-01-2026',
    market_value: 'Mkt.Value:Rs. 774,900',
  });
  assert.equal(valid.parsedPayload.registration_date, '2026-01-01');
  assert.equal(valid.parsedPayload.market_value_amount, '774900');
  assert.equal(valid.validationErrors.length, 0);

  const malformed = parseSroRecord({
    ...sourceRows[0],
    registration_date: '32-01-2026',
    market_value: 'Mkt.Value:Rs. 1,2,00',
  });
  assert.ok(malformed.validationErrors.includes('registration_date: invalid calendar date'));
  assert.ok(malformed.validationErrors.includes('market_value: invalid digit grouping'));

  const missingIdentity = parseSroRecord({ ...sourceRows[0], document_no: '' });
  assert.ok(missingIdentity.validationErrors.some((error) => error.includes('document_no')));
  assert.equal(missingIdentity.parsedPayload.document_identity, null);
});

test('historical and daily SRO imports share idempotent versioning and preserve corrections', async () => {
  const database = await createTestDatabase();

  try {
    const backfill = await importSroRows(database, sourceRows, {
      runKind: 'historical_backfill',
      parserVersion: '1.0.0',
    });
    const daily = await importSroRows(
      database,
      sourceRows.map((row) => ({ ...row, fetched_at: '2026-10-06 09:00:00' })),
      { runKind: 'daily', parserVersion: '1.0.0' },
    );
    const corrected = await importSroRows(
      database,
      [{ ...sourceRows[0], consideration_value: 'Cons.Value:Rs. 9000000' }],
      { runKind: 'daily', parserVersion: '1.0.1' },
    );

    assert.equal(backfill.recordCount, 2);
    assert.equal(daily.recordCount, 2);
    assert.equal(corrected.errorCount, 0);

    const counts = await database.query(`
      SELECT
        (SELECT count(*)::integer FROM public.source_observations) AS observations,
        (SELECT count(*)::integer FROM public.source_observation_sightings) AS sightings,
        (SELECT count(*)::integer FROM public.import_runs WHERE run_kind = 'daily') AS daily_runs
    `);
    assert.deepEqual(counts.rows[0], { observations: 3, sightings: 5, daily_runs: 2 });

    const invalid = await importSroRows(
      database,
      [{ ...sourceRows[0], registration_date: 'not-a-date', consideration_value: 'unknown' }],
      { runKind: 'daily', parserVersion: '1.0.1' },
    );
    assert.equal(invalid.errorCount, 1);
    assert.equal(invalid.validationReport.length, 1);

    const invalidRecord = await database.query(
      `SELECT parse_status, validation_errors
       FROM public.source_observations
       WHERE content_hash = $1`,
      [hashSroPayload({ ...sourceRows[0], registration_date: 'not-a-date', consideration_value: 'unknown' })],
    );
    assert.equal(invalidRecord.rows[0].parse_status, 'invalid');
    assert.equal(invalidRecord.rows[0].validation_errors.length, 2);
  } finally {
    await database.close();
  }
});