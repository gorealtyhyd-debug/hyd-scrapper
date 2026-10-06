import { createHash } from 'node:crypto';
import { parse } from 'csv-parse/sync';
import { sroDocumentIdentity, sroScheduleIdentity } from './sro-identities.mjs';

function canonicalize(value) {
  if (Array.isArray(value)) {
    return value.map(canonicalize);
  }
  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.keys(value)
        .sort()
        .map((key) => [key, canonicalize(value[key])]),
    );
  }
  return value;
}

export function parseSroCsv(csvText) {
  return parse(csvText, {
    bom: true,
    columns: true,
    skip_empty_lines: true,
  });
}

export function hashSroPayload(row) {
  const content = Object.fromEntries(
    Object.entries(row).filter(([key]) => !['fetched_at', 'id'].includes(key.trim().toLowerCase())),
  );
  return createHash('sha256').update(JSON.stringify(canonicalize(content))).digest('hex');
}

function parseSroDate(value, fieldName, errors) {
  const sourceValue = String(value ?? '').trim().replace(/^\([A-Z]\)\s*/i, '');
  if (!sourceValue) {
    return null;
  }

  let year;
  let month;
  let day;
  const dayFirst = sourceValue.match(/^(\d{2})-(\d{2})-(\d{4})$/);
  const isoDate = sourceValue.match(/^(\d{4})-(\d{2})-(\d{2})$/);

  if (dayFirst) {
    [, day, month, year] = dayFirst;
  } else if (isoDate) {
    [, year, month, day] = isoDate;
  } else {
    errors.push(`${fieldName}: unsupported date format`);
    return null;
  }

  const date = new Date(Date.UTC(Number(year), Number(month) - 1, Number(day)));
  if (
    date.getUTCFullYear() !== Number(year)
    || date.getUTCMonth() !== Number(month) - 1
    || date.getUTCDate() !== Number(day)
  ) {
    errors.push(`${fieldName}: invalid calendar date`);
    return null;
  }

  return `${year}-${month}-${day}`;
}

function parseSroAmount(value, fieldName, errors) {
  const sourceValue = String(value ?? '').trim();
  if (!sourceValue) {
    return null;
  }

  const labeledValue = sourceValue.replace(/^(?:Mkt\.Value|Cons\.Value|Market value|Consideration value)\s*:\s*/i, '').trim();
  const amountMatch = labeledValue.match(/^(?:Rs\.?\s*)?([0-9][0-9,]*(?:\.[0-9]+)?)$/i);
  if (!amountMatch) {
    errors.push(`${fieldName}: invalid monetary value`);
    return null;
  }

  const amount = amountMatch[1];
  if (!/^(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d+)?$/.test(amount)) {
    errors.push(`${fieldName}: invalid digit grouping`);
    return null;
  }

  return amount.replaceAll(',', '');
}

export function parseSroRecord(row) {
  const validationErrors = [];
  let documentIdentity = null;
  let scheduleIdentity = null;

  try {
    documentIdentity = sroDocumentIdentity(row);
    scheduleIdentity = sroScheduleIdentity(row);
  } catch (error) {
    validationErrors.push(error.message);
  }

  const parsedPayload = {
    document_identity: documentIdentity,
    schedule_identity: scheduleIdentity,
    execution_date: parseSroDate(row.execution_date, 'execution_date', validationErrors),
    registration_date: parseSroDate(row.registration_date, 'registration_date', validationErrors),
    presentation_date: parseSroDate(row.presentation_date, 'presentation_date', validationErrors),
    market_value_amount: parseSroAmount(row.market_value, 'market_value', validationErrors),
    consideration_amount: parseSroAmount(row.consideration_value, 'consideration_value', validationErrors),
  };

  return { parsedPayload, validationErrors };
}

function validTimestamp(value) {
  if (!value || Number.isNaN(Date.parse(value))) {
    return null;
  }
  return new Date(value).toISOString();
}

async function findOrCreateOffice(client, row) {
  const code = String(row.sro_code ?? '').trim();
  if (!code) {
    return null;
  }

  const name = String(row.sro_name ?? '').trim() || code;
  const result = await client.query(
    `INSERT INTO public.registration_offices (source_system_code, sro_code, name)
     VALUES ('telangana_sro', $1, $2)
     ON CONFLICT (source_system_code, sro_code)
     DO UPDATE SET name = EXCLUDED.name
     RETURNING id`,
    [code, name],
  );
  return result.rows[0].id;
}

export async function importSroRows(client, rows, { runKind, parserVersion }) {
  if (!['historical_backfill', 'daily', 'replay', 'manual'].includes(runKind)) {
    throw new TypeError(`Unsupported import run kind: ${runKind}`);
  }

  await client.query('BEGIN');
  try {
    const runResult = await client.query(
      `INSERT INTO public.import_runs (source_system_code, run_kind)
       VALUES ('telangana_sro', $1)
       RETURNING id`,
      [runKind],
    );
    const importRunId = runResult.rows[0].id;
    let invalidCount = 0;
    const validationReport = [];

    for (const row of rows) {
      const officeId = await findOrCreateOffice(client, row);
      const contentHash = hashSroPayload(row);
      const { parsedPayload, validationErrors } = parseSroRecord(row);

      const sourceRecordKey = parsedPayload.schedule_identity ?? JSON.stringify(['invalid', contentHash]);
      const observationResult = await client.query(
        `INSERT INTO public.source_observations
          (source_system_code, registration_office_id, source_record_type, source_record_key,
           content_hash, raw_payload, parsed_payload, parser_version, parse_status, validation_errors)
         VALUES ('telangana_sro', $1, 'sro_schedule', $2, $3, $4::jsonb, $5::jsonb, $6, $7, $8::jsonb)
         ON CONFLICT (source_system_code, registration_office_id, source_record_type, source_record_key, content_hash)
         DO NOTHING
         RETURNING id`,
        [
          officeId,
          sourceRecordKey,
          contentHash,
          JSON.stringify(row),
          JSON.stringify(parsedPayload),
          parserVersion,
          validationErrors.length ? 'invalid' : 'pending',
          JSON.stringify(validationErrors),
        ],
      );

      let observationId = observationResult.rows[0]?.id;
      if (!observationId) {
        const existing = await client.query(
          `SELECT id FROM public.source_observations
           WHERE source_system_code = 'telangana_sro'
             AND registration_office_id IS NOT DISTINCT FROM $1
             AND source_record_type = 'sro_schedule'
             AND source_record_key = $2
             AND content_hash = $3`,
          [officeId, sourceRecordKey, contentHash],
        );
        observationId = existing.rows[0].id;
      }

      const sourceFetchedAt = validTimestamp(row.fetched_at);
      await client.query(
        `INSERT INTO public.source_observation_sightings
          (source_observation_id, import_run_id, fetched_at, response_metadata)
         VALUES ($1, $2, COALESCE($3::timestamptz, clock_timestamp()), $4::jsonb)
         ON CONFLICT (source_observation_id, import_run_id) DO NOTHING`,
        [
          observationId,
          importRunId,
          sourceFetchedAt,
          JSON.stringify({ source_url: row.source_url ?? null, source_row_id: row.id ?? null }),
        ],
      );

      invalidCount += validationErrors.length ? 1 : 0;
      if (validationErrors.length) {
        validationReport.push({ sourceRecordKey, errors: validationErrors });
      }
    }

    await client.query(
      `UPDATE public.import_runs
       SET run_status = $2,
           record_count = $3,
           error_count = $4,
            metadata = $5::jsonb,
           finished_at = clock_timestamp()
       WHERE id = $1`,
      [
        importRunId,
        invalidCount ? 'completed_with_errors' : 'completed',
        rows.length,
        invalidCount,
        JSON.stringify({ validation_report: validationReport }),
      ],
    );
    await client.query('COMMIT');
    return { importRunId, recordCount: rows.length, errorCount: invalidCount, validationReport };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  }
}