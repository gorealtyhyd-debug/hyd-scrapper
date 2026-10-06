import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createTestDatabase } from './test-database.mjs';

test('document parties preserve source roles and allow party reuse across documents', async () => {
  const database = await createTestDatabase();

  try {
    await database.exec(`
      INSERT INTO public.registration_offices (id, source_system_code, sro_code, name)
      VALUES ('00000000-0000-0000-0000-000000000001', 'telangana_sro', '1522', 'Office A');
      INSERT INTO public.registration_documents
        (id, source_system_code, registration_office_id, registration_year, document_no)
      VALUES
        ('00000000-0000-0000-0000-000000000002', 'telangana_sro', '00000000-0000-0000-0000-000000000001', 2026, '1'),
        ('00000000-0000-0000-0000-000000000003', 'telangana_sro', '00000000-0000-0000-0000-000000000001', 2026, '2');
      INSERT INTO public.parties (id, party_type, canonical_name, normalized_name)
      VALUES ('00000000-0000-0000-0000-000000000004', 'person', 'Sainyam Jain', 'sainyam jain');
      INSERT INTO public.party_aliases
        (party_id, source_system_code, raw_name, normalized_name, source_reference, match_status)
      VALUES ('00000000-0000-0000-0000-000000000004', 'telangana_sro', 'SAINYAM JAIN', 'sainyam jain', 'doc-1-party-2', 'accepted');
      INSERT INTO public.registration_document_parties
        (registration_document_id, party_id, party_role_code, source_role_code, source_party_sequence, source_name_as_recorded)
      VALUES
        ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000004', 'CL', 'CL', 2, 'Sainyam Jain'),
        ('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000004', 'EX', 'EX', 1, 'Sainyam Jain');
    `);

    const links = await database.query(
      `SELECT registration_document_id, party_role_code, source_role_code, source_name_as_recorded
       FROM public.registration_document_parties
       ORDER BY registration_document_id`,
    );
    assert.equal(links.rows.length, 2);
    assert.equal(links.rows[0].source_role_code, 'CL');
    assert.equal(links.rows[0].source_name_as_recorded, 'Sainyam Jain');

    await assert.rejects(
      database.query(`
        INSERT INTO public.registration_document_parties
          (registration_document_id, party_role_code, source_role_code, source_name_as_recorded)
        VALUES ('00000000-0000-0000-0000-000000000002', 'UNKNOWN_ROLE', 'ZZ', 'Unknown');
      `),
    );
  } finally {
    await database.close();
  }
});