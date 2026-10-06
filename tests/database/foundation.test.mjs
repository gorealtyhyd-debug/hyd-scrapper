import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createTestDatabase } from './test-database.mjs';

test('foundation migrations apply to a clean PostgreSQL database', async () => {
  const database = await createTestDatabase();

  try {
    await database.exec(`
      CREATE TABLE public.trigger_probe (
        id integer PRIMARY KEY,
        updated_at timestamptz NOT NULL
      );
      CREATE TRIGGER trigger_probe_updated_at
        BEFORE UPDATE ON public.trigger_probe
        FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
      INSERT INTO public.trigger_probe VALUES (1, '2000-01-01T00:00:00Z');
      UPDATE public.trigger_probe SET id = 1 WHERE id = 1;
    `);

    const result = await database.query(
      'SELECT updated_at > $1::timestamptz AS was_updated FROM public.trigger_probe WHERE id = 1',
      ['2000-01-01T00:00:00Z'],
    );

    assert.equal(result.rows[0].was_updated, true);
  } finally {
    await database.close();
  }
});