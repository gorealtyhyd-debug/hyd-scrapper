import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createTestDatabase } from './test-database.mjs';

test('survey identifiers are unique within office and village context', async () => {
  const database = await createTestDatabase();

  try {
    await database.exec(`
      INSERT INTO public.geographic_areas (id, area_type, source_name, normalized_name)
      VALUES
        ('00000000-0000-0000-0000-000000000001', 'state', 'Telangana', 'telangana'),
        ('00000000-0000-0000-0000-000000000002', 'district', 'District A', 'district a'),
        ('00000000-0000-0000-0000-000000000003', 'district', 'District B', 'district b'),
        ('00000000-0000-0000-0000-000000000004', 'village', 'Village', 'village a'),
        ('00000000-0000-0000-0000-000000000005', 'village', 'Village', 'village b');
      INSERT INTO public.registration_offices (id, source_system_code, sro_code, name)
      VALUES
        ('00000000-0000-0000-0000-000000000011', 'telangana_sro', '1522', 'Office A'),
        ('00000000-0000-0000-0000-000000000012', 'telangana_sro', '1523', 'Office B');
      INSERT INTO public.survey_identifiers
        (registration_office_id, village_area_id, raw_identifier, normalized_identifier)
      VALUES
        ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000004', '264', '264'),
        ('00000000-0000-0000-0000-000000000012', '00000000-0000-0000-0000-000000000005', '264', '264'),
        ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000004', '264/1', '264/1');
    `);

    const identifiers = await database.query(
      'SELECT count(*)::integer AS count FROM public.survey_identifiers WHERE normalized_identifier = $1',
      ['264'],
    );
    assert.equal(identifiers.rows[0].count, 2);

    const surveyRows = await database.query(
      'SELECT id, normalized_identifier FROM public.survey_identifiers ORDER BY normalized_identifier',
    );
    const baseSurvey = surveyRows.rows.find((row) => row.normalized_identifier === '264');
    const subdivision = surveyRows.rows.find((row) => row.normalized_identifier === '264/1');

    await database.query(
      `INSERT INTO public.survey_identifier_aliases
        (survey_identifier_id, raw_alias, normalized_alias, source_system_code, source_reference)
       VALUES ($1, 'Survey No. 264', 'survey no. 264', 'telangana_sro', 'source-row-42')`,
      [baseSurvey.id],
    );
    await database.query(
      `INSERT INTO public.survey_identifier_relations
        (from_survey_identifier_id, to_survey_identifier_id, relation_type, source_reference)
       VALUES ($1, $2, 'subdivision', 'document-41 schedule-2')`,
      [baseSurvey.id, subdivision.id],
    );

    const aliases = await database.query(
      'SELECT source_reference FROM public.survey_identifier_aliases WHERE survey_identifier_id = $1',
      [baseSurvey.id],
    );
    const relations = await database.query(
      'SELECT relation_type, source_reference FROM public.survey_identifier_relations WHERE from_survey_identifier_id = $1',
      [baseSurvey.id],
    );
    assert.equal(aliases.rows[0].source_reference, 'source-row-42');
    assert.equal(relations.rows[0].relation_type, 'subdivision');
    assert.equal(relations.rows[0].source_reference, 'document-41 schedule-2');

    await assert.rejects(
      database.exec(`
        INSERT INTO public.survey_identifiers
          (registration_office_id, village_area_id, raw_identifier, normalized_identifier)
        VALUES
          ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000004', '264', '264');
      `),
    );

    await assert.rejects(
      database.query(
        `INSERT INTO public.survey_identifiers
          (registration_office_id, village_area_id, raw_identifier, normalized_identifier)
         VALUES ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000002', '264', 'district-survey')`,
      ),
    );
  } finally {
    await database.close();
  }
});