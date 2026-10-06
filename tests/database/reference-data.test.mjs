import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import { createTestDatabase } from './test-database.mjs';

test('reference seeds are repeatable and constrain machine codes', async () => {
  const database = await createTestDatabase();

  try {
    const before = await database.query(
      'SELECT code FROM public.document_types ORDER BY code',
    );

    await database.exec(
      await readFile(new URL('../../supabase/migrations/20261005000200_reference_data.sql', import.meta.url), 'utf8'),
    );

    const after = await database.query(
      'SELECT code FROM public.document_types ORDER BY code',
    );

    assert.deepEqual(after.rows, before.rows);
    assert.ok(before.rows.some((row) => row.code === 'sale_deed'));

    await assert.rejects(
      database.query(
        "INSERT INTO public.listing_types (code, label) VALUES ('Invalid Code', 'Bad')",
      ),
    );
  } finally {
    await database.close();
  }
});