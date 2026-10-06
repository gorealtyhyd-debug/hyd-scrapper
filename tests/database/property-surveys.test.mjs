import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createTestDatabase } from './test-database.mjs';

test('property-to-survey links retain review and evidence state', async () => {
  const database = await createTestDatabase();

  try {
    await database.exec(`
      INSERT INTO public.geographic_areas (id, area_type, source_name, normalized_name)
      VALUES ('00000000-0000-0000-0000-000000000001', 'village', 'Village A', 'village a');
      INSERT INTO public.registration_offices (id, source_system_code, sro_code, name)
      VALUES ('00000000-0000-0000-0000-000000000002', 'telangana_sro', '1522', 'Serilingampally');
      INSERT INTO public.survey_identifiers
        (id, registration_office_id, village_area_id, raw_identifier, normalized_identifier)
      VALUES ('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', '264/P', '264/p');
      INSERT INTO public.properties
        (id, property_type_code, display_name, normalized_name)
      VALUES ('00000000-0000-0000-0000-000000000004', 'open_plot', 'Plot 38', 'plot 38');
      INSERT INTO public.property_survey_identifiers
        (property_id, survey_identifier_id, match_method, match_status, confidence, source_reference)
      VALUES
        ('00000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000003', 'normalized_text', 'pending', 0.6500, 'source-row-17'),
        ('00000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000003', 'manual_review', 'accepted', 1.0000, 'review-1');
      INSERT INTO public.property_listings
        (property_id, listing_type_code, listing_status_code, asking_price, currency_code)
      VALUES ('00000000-0000-0000-0000-000000000004', 'sale', 'active', 5000000, 'INR');
    `);

    const link = await database.query(
      'SELECT match_status, confidence, source_reference FROM public.property_survey_identifiers',
    );
    assert.deepEqual(link.rows[0], {
      match_status: 'pending',
      confidence: '0.6500',
      source_reference: 'source-row-17',
    });

    const inventoryRead = await database.query(
      `SELECT p.display_name AS property_name, s.raw_identifier AS survey_number,
              l.listing_type_code, l.asking_price, l.currency_code
       FROM public.properties AS p
       JOIN public.property_survey_identifiers AS ps
         ON ps.property_id = p.id AND ps.match_status = 'accepted'
       JOIN public.survey_identifiers AS s ON s.id = ps.survey_identifier_id
       LEFT JOIN public.property_listings AS l
         ON l.property_id = p.id AND l.listing_status_code = 'active'
       WHERE p.id = $1
       ORDER BY s.normalized_identifier, l.listing_type_code`,
      ['00000000-0000-0000-0000-000000000004'],
    );
    assert.deepEqual(inventoryRead.rows[0], {
      property_name: 'Plot 38',
      survey_number: '264/P',
      listing_type_code: 'sale',
      asking_price: '5000000.00',
      currency_code: 'INR',
    });

    await assert.rejects(
      database.query(`
        INSERT INTO public.property_survey_identifiers
          (property_id, survey_identifier_id, match_method, match_status, confidence)
        VALUES
          ('00000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000003', 'normalized_text', 'accepted', 1.2);
      `),
    );
  } finally {
    await database.close();
  }
});