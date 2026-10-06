import { parseSroRecord } from './sro-importer.mjs';

function documentTypeCode(label) {
  const normalized = String(label ?? '').trim().toUpperCase();
  if (!normalized) return null;
  if (normalized.includes('SALE DEED')) return 'sale_deed';
  if (normalized.includes('DEPOSIT OF TITLE DEEDS')) return 'deposit_title_deeds';
  if (normalized.includes('MORTGAGE WITHOUT POSSESSION')) return 'mortgage_without_possession';
  if (normalized.includes('RELEASE AMONG FAMILY')) return 'family_release';
  if (normalized.includes('RELEASE OF MORTGAGE')) return 'mortgage_release';
  if (normalized.includes('DEVELOPMENT AGREEMENT')) return 'development_agreement';
  if (normalized.includes('GIFT')) return 'gift_deed';
  if (normalized.includes('LEASE')) return 'lease_deed';
  if (normalized.includes('GPA') || normalized.includes('POWER OF ATTORNEY')) return 'general_power_of_attorney';
  if (normalized.includes('RECTIFICATION')) return 'rectification';
  if (normalized.includes('CANCELLATION')) return 'cancellation';
  if (normalized.includes('MORTGAGE')) return 'mortgage_deed';
  return 'other';
}

export async function promoteSroObservations(client, observationIds) {
  await client.query('BEGIN');
  try {
    let promotedCount = 0;

    for (const observationId of observationIds) {
      const result = await client.query(
        `SELECT id, registration_office_id, raw_payload, parse_status
         FROM public.source_observations
         WHERE id = $1 AND source_system_code = 'telangana_sro'`,
        [observationId],
      );
      const observation = result.rows[0];
      if (!observation) {
        throw new Error(`SRO source observation not found: ${observationId}`);
      }
      if (observation.parse_status === 'invalid') {
        continue;
      }

      const raw = observation.raw_payload;
      const { parsedPayload, validationErrors } = parseSroRecord(raw);
      const registrationYear = Number.parseInt(raw.registration_year, 10);
      const bookNo = String(raw.book_no ?? '').trim();
      const documentNo = String(raw.document_no ?? '').trim();
      const scheduleNo = String(raw.schedule_no ?? '').trim();
      if (
        validationErrors.length
        || !observation.registration_office_id
        || !Number.isInteger(registrationYear)
        || !bookNo
        || !documentNo
        || !scheduleNo
      ) {
        await client.query(
          `UPDATE public.source_observations
           SET parse_status = 'invalid', validation_errors = $2::jsonb
           WHERE id = $1`,
          [observationId, JSON.stringify([
            ...validationErrors,
            ...(!observation.registration_office_id ? ['missing registration office'] : []),
            ...(!Number.isInteger(registrationYear) ? ['invalid registration_year'] : []),
            ...(!bookNo ? ['missing book_no'] : []),
            ...(!documentNo ? ['missing document_no'] : []),
            ...(!scheduleNo ? ['missing schedule_no'] : []),
          ])],
        );
        continue;
      }

      const documentResult = await client.query(
        `INSERT INTO public.registration_documents
          (source_system_code, registration_office_id, registration_year, book_no, document_no,
           document_type_code, document_type_as_recorded, execution_date, registration_date,
           presentation_date, market_value, consideration_value, volume_no, cd_no)
         VALUES ('telangana_sro', $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
         ON CONFLICT (source_system_code, registration_office_id, registration_year, book_no, document_no)
         DO UPDATE SET
           document_type_code = COALESCE(EXCLUDED.document_type_code, registration_documents.document_type_code),
           document_type_as_recorded = COALESCE(NULLIF(EXCLUDED.document_type_as_recorded, ''), registration_documents.document_type_as_recorded),
           execution_date = COALESCE(EXCLUDED.execution_date, registration_documents.execution_date),
           registration_date = COALESCE(EXCLUDED.registration_date, registration_documents.registration_date),
           presentation_date = COALESCE(EXCLUDED.presentation_date, registration_documents.presentation_date),
           market_value = COALESCE(EXCLUDED.market_value, registration_documents.market_value),
           consideration_value = COALESCE(EXCLUDED.consideration_value, registration_documents.consideration_value),
           volume_no = COALESCE(EXCLUDED.volume_no, registration_documents.volume_no),
           cd_no = COALESCE(EXCLUDED.cd_no, registration_documents.cd_no)
         RETURNING id`,
        [
          observation.registration_office_id,
          registrationYear,
          bookNo,
          documentNo,
          documentTypeCode(raw.document_description),
          String(raw.document_description ?? ''),
          parsedPayload.execution_date,
          parsedPayload.registration_date,
          parsedPayload.presentation_date,
          parsedPayload.market_value_amount,
          parsedPayload.consideration_amount,
          raw.volume_no || null,
          raw.cd_no || null,
        ],
      );
      const documentId = documentResult.rows[0].id;

      await client.query(
        `INSERT INTO public.registration_document_observations
          (registration_document_id, source_observation_id)
         VALUES ($1, $2)
         ON CONFLICT DO NOTHING`,
        [documentId, observationId],
      );

      const scheduleResult = await client.query(
        `INSERT INTO public.registration_schedules (registration_document_id, schedule_number)
         VALUES ($1, $2)
         ON CONFLICT (registration_document_id, schedule_number)
         DO UPDATE SET schedule_number = EXCLUDED.schedule_number
         RETURNING id`,
        [documentId, scheduleNo],
      );
      const scheduleId = scheduleResult.rows[0].id;

      await client.query(
        `INSERT INTO public.registration_schedule_observations
          (registration_schedule_id, source_observation_id, raw_property_description, parsed_property_details)
         VALUES ($1, $2, $3, $4::jsonb)
         ON CONFLICT (registration_schedule_id, source_observation_id)
         DO UPDATE SET raw_property_description = EXCLUDED.raw_property_description,
                       parsed_property_details = EXCLUDED.parsed_property_details`,
        [scheduleId, observationId, String(raw.property_details ?? ''), JSON.stringify(parsedPayload)],
      );

      await client.query(
        `UPDATE public.source_observations
         SET parse_status = 'promoted'
         WHERE id = $1 AND parse_status <> 'invalid'`,
        [observationId],
      );
      promotedCount += 1;
    }

    await client.query('COMMIT');
    return { promotedCount };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  }
}