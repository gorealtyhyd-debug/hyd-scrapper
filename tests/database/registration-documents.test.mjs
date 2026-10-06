import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createTestDatabase } from './test-database.mjs';

test('registration documents and schedules have separate scoped identities', async () => {
  const database = await createTestDatabase();

  try {
    await database.exec(`
      INSERT INTO public.registration_offices (id, source_system_code, sro_code, name)
      VALUES
        ('00000000-0000-0000-0000-000000000001', 'telangana_sro', '1522', 'Office A'),
        ('00000000-0000-0000-0000-000000000002', 'telangana_sro', '1523', 'Office B');
      INSERT INTO public.registration_documents
        (id, source_system_code, registration_office_id, registration_year, book_no,
         document_no, document_type_as_recorded, document_type_code, consideration_value)
      VALUES
        ('00000000-0000-0000-0000-000000000011', 'telangana_sro', '00000000-0000-0000-0000-000000000001', 2026, '1', '1', 'SALE DEED', 'sale_deed', 8150000),
        ('00000000-0000-0000-0000-000000000012', 'telangana_sro', '00000000-0000-0000-0000-000000000002', 2026, '1', '1', 'CUSTOM INSTRUMENT TYPE', 'other', 0);
      INSERT INTO public.registration_schedules
        (registration_document_id, schedule_number)
      VALUES
        ('00000000-0000-0000-0000-000000000011', '1'),
        ('00000000-0000-0000-0000-000000000011', '2'),
        ('00000000-0000-0000-0000-000000000012', '1');
    `);

    const identities = await database.query(`
      SELECT d.document_no, d.document_type_as_recorded, count(s.id)::integer AS schedules
      FROM public.registration_documents AS d
      LEFT JOIN public.registration_schedules AS s ON s.registration_document_id = d.id
      GROUP BY d.id
      ORDER BY d.registration_office_id
    `);
    assert.equal(identities.rows.length, 2);
    assert.equal(identities.rows[0].schedules, 2);
    assert.equal(identities.rows[1].document_type_as_recorded, 'CUSTOM INSTRUMENT TYPE');

    await assert.rejects(
      database.query(`
        INSERT INTO public.registration_documents
          (source_system_code, registration_office_id, registration_year, book_no, document_no)
        VALUES ('telangana_sro', '00000000-0000-0000-0000-000000000001', 2026, '1', '1');
      `),
    );

    await assert.rejects(
      database.query(`
        INSERT INTO public.registration_schedules (registration_document_id, schedule_number)
        VALUES ('00000000-0000-0000-0000-000000000011', '1');
      `),
    );
  } finally {
    await database.close();
  }
});