import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createTestDatabase } from './test-database.mjs';

test('audit events capture state and assignment changes without storing mobile values', async () => {
  const database = await createTestDatabase();
  const adminId = '00000000-0000-0000-0000-000000000001';

  try {
    await database.exec(`
      INSERT INTO auth.users (id) VALUES ('${adminId}');
      INSERT INTO public.user_profiles (auth_user_id, display_name) VALUES ('${adminId}', 'Admin');
      SELECT set_config('request.jwt.claim.sub', '${adminId}', false);
      INSERT INTO public.user_role_assignments (auth_user_id, role_code) VALUES ('${adminId}', 'admin');
      INSERT INTO public.properties (id, property_type_code, display_name, normalized_name)
      VALUES ('00000000-0000-0000-0000-000000000002', 'villa', 'Villa 1', 'villa 1');
    `);

    await database.query('SET ROLE authenticated');
    await database.query(
      `INSERT INTO public.property_assignments (auth_user_id, property_id)
       VALUES ($1, $2)`,
      [adminId, '00000000-0000-0000-0000-000000000002'],
    );
    await database.query(
      `INSERT INTO public.leads (property_id, lead_status_code)
       VALUES ($1, 'pending')`,
      ['00000000-0000-0000-0000-000000000002'],
    );
    await database.query(
      `UPDATE public.leads SET lead_status_code = 'rent'
       WHERE property_id = $1`,
      ['00000000-0000-0000-0000-000000000002'],
    );
    await database.query('RESET ROLE');
    await database.query(
      `INSERT INTO public.mobile_captures
        (property_id, phone_as_captured, normalized_phone, capture_source)
       VALUES ($1, '9000000000', '+919000000000', 'manual')`,
      ['00000000-0000-0000-0000-000000000002'],
    );

    const events = await database.query(
      `SELECT event_sequence, entity_type, event_type, actor_user_id, before_summary, after_summary
       FROM public.audit_events ORDER BY event_sequence`,
    );
    assert.ok(events.rows.some((event) => event.entity_type === 'property_assignments'));
    assert.ok(events.rows.some((event) => event.entity_type === 'lead' && event.event_type === 'status_changed'));
    const mobileCaptureEvent = events.rows.find((event) => event.entity_type === 'mobile_capture');
    assert.ok(mobileCaptureEvent);
    assert.equal(JSON.stringify(mobileCaptureEvent.after_summary).includes('9000000000'), false);
    assert.ok(events.rows.every((event) => event.actor_user_id === adminId));
    const leadTransition = events.rows.find(
      (event) => event.entity_type === 'lead' && event.event_type === 'status_changed',
    );
    assert.equal(leadTransition.before_summary.status, 'pending');
    assert.equal(leadTransition.after_summary.status, 'rent');

    await assert.rejects(
      database.query('DELETE FROM public.audit_events WHERE event_sequence = $1', [events.rows[0].event_sequence]),
      /audit events are append-only/,
    );
  } finally {
    await database.close();
  }
});