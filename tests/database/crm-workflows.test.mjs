import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createTestDatabase } from './test-database.mjs';

test('mobile captures, lead transitions, and follow-ups retain actor and history', async () => {
  const database = await createTestDatabase();

  try {
    await database.exec(`
      INSERT INTO auth.users (id)
      VALUES ('00000000-0000-0000-0000-000000000001');
      INSERT INTO public.properties (id, property_type_code, display_name, normalized_name)
      VALUES ('00000000-0000-0000-0000-000000000002', 'villa', 'Villa 7', 'villa 7');
      INSERT INTO public.crm_contacts (id, display_name, created_by)
      VALUES ('00000000-0000-0000-0000-000000000003', 'Contact One', '00000000-0000-0000-0000-000000000001');
      INSERT INTO public.crm_contact_methods
        (contact_id, method_type, raw_value, normalized_value, consent_status, is_primary)
      VALUES ('00000000-0000-0000-0000-000000000003', 'mobile', '+91 90000 00000', '+919000000000', 'unknown', true);
      SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
      INSERT INTO public.mobile_captures
        (property_id, contact_id, captured_by, phone_as_captured, normalized_phone, capture_source)
      VALUES ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001', '+91 90000 00000', '+919000000000', 'manual');
      INSERT INTO public.leads
        (id, property_id, contact_id, lead_status_code, expected_sale_price, created_by)
      VALUES ('00000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000003', 'pending', 12000000, '00000000-0000-0000-0000-000000000001');
      UPDATE public.leads SET lead_status_code = 'resale'
      WHERE id = '00000000-0000-0000-0000-000000000004';
      INSERT INTO public.lead_follow_ups
        (lead_id, assigned_to, created_by, scheduled_at, note)
      VALUES ('00000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', '2026-10-10T10:00:00Z', 'Call back');
    `);

    const history = await database.query(
      `SELECT from_status_code, to_status_code, actor_user_id
       FROM public.lead_status_history WHERE lead_id = $1 ORDER BY event_sequence`,
      ['00000000-0000-0000-0000-000000000004'],
    );
    assert.equal(history.rows.length, 2);
    assert.deepEqual(history.rows.map((row) => row.to_status_code), ['pending', 'resale']);
    assert.equal(history.rows[1].from_status_code, 'pending');
    assert.equal(history.rows[1].actor_user_id, '00000000-0000-0000-0000-000000000001');

    const captures = await database.query(
      'SELECT phone_as_captured, captured_by FROM public.mobile_captures WHERE property_id = $1',
      ['00000000-0000-0000-0000-000000000002'],
    );
    assert.equal(captures.rows[0].phone_as_captured, '+91 90000 00000');
    assert.equal(captures.rows[0].captured_by, '00000000-0000-0000-0000-000000000001');

    const followUps = await database.query(
      'SELECT follow_up_status, scheduled_at FROM public.lead_follow_ups WHERE lead_id = $1',
      ['00000000-0000-0000-0000-000000000004'],
    );
    assert.equal(followUps.rows[0].follow_up_status, 'scheduled');

    await assert.rejects(
      database.query(`
        INSERT INTO public.mobile_captures (phone_as_captured, capture_source)
        VALUES ('9000000000', 'manual');
      `),
    );
  } finally {
    await database.close();
  }
});