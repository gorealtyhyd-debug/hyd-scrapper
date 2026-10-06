import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createTestDatabase } from './test-database.mjs';

test('sale and rental listings remain separate and status changes are recorded', async () => {
  const database = await createTestDatabase();

  try {
    await database.exec(`
      INSERT INTO auth.users (id)
      VALUES ('00000000-0000-0000-0000-000000000001');
      INSERT INTO public.properties (id, property_type_code, display_name, normalized_name)
      VALUES ('00000000-0000-0000-0000-000000000002', 'apartment_flat', 'Flat 1201', 'flat 1201');
      SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
      INSERT INTO public.property_listings
        (id, property_id, listing_type_code, listing_status_code, asking_price, currency_code, published_at)
      VALUES
        ('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000002', 'sale', 'active', 12500000, 'INR', '2026-01-01T00:00:00Z'),
        ('00000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000002', 'rent', 'draft', 45000, 'INR', '2026-03-01T00:00:00Z');
      UPDATE public.property_listings SET listing_status_code = 'closed'
      WHERE id = '00000000-0000-0000-0000-000000000003';
    `);

    const listings = await database.query(
      'SELECT listing_type_code FROM public.property_listings ORDER BY listing_type_code',
    );
    assert.deepEqual(listings.rows.map((row) => row.listing_type_code), ['rent', 'sale']);

    const history = await database.query(
      `SELECT from_status_code, to_status_code, actor_user_id
       FROM public.property_listing_status_history
       WHERE property_listing_id = $1
        ORDER BY event_sequence`,
      ['00000000-0000-0000-0000-000000000003'],
    );
    assert.equal(history.rows.length, 2);
    assert.equal(history.rows[0].from_status_code, null);
    assert.equal(history.rows[0].to_status_code, 'active');
    assert.equal(history.rows[1].from_status_code, 'active');
    assert.equal(history.rows[1].to_status_code, 'closed');
    assert.equal(history.rows[1].actor_user_id, '00000000-0000-0000-0000-000000000001');

    await assert.rejects(
      database.query(`
        INSERT INTO public.property_listings
          (property_id, listing_type_code, listing_status_code, rent_period)
        VALUES ('00000000-0000-0000-0000-000000000002', 'sale', 'active', 'month');
      `),
    );
  } finally {
    await database.close();
  }
});