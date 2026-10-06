import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createTestDatabase } from './test-database.mjs';

const callerId = '00000000-0000-0000-0000-000000000001';
const otherCallerId = '00000000-0000-0000-0000-000000000002';
const thirdPartyId = '00000000-0000-0000-0000-000000000003';
const propertyId = '00000000-0000-0000-0000-000000000010';
const contactMethodId = '00000000-0000-0000-0000-000000000020';
const propertyContactMatchId = '00000000-0000-0000-0000-000000000030';
const saleIntentId = '00000000-0000-0000-0000-000000000040';
const rentIntentId = '00000000-0000-0000-0000-000000000041';

async function assumeUser(database, authUserId) {
  await database.query("SELECT set_config('request.jwt.claim.sub', $1, false)", [authUserId]);
  await database.query('SET ROLE authenticated');
}

test('owner contact evidence and sale/rent intent tracks remain separate and assignment-scoped', async () => {
  const database = await createTestDatabase();

  try {
    await database.exec(`
      INSERT INTO auth.users (id) VALUES ('${callerId}'), ('${otherCallerId}'), ('${thirdPartyId}');
      INSERT INTO public.user_profiles (auth_user_id, display_name) VALUES
        ('${callerId}', 'Telecaller'), ('${otherCallerId}', 'Other Telecaller'), ('${thirdPartyId}', 'Third Party');
      SELECT set_config('request.jwt.claim.sub', '${callerId}', false);
      INSERT INTO public.user_role_assignments (auth_user_id, role_code) VALUES
        ('${callerId}', 'telecaller'), ('${otherCallerId}', 'telecaller'), ('${thirdPartyId}', 'third_party');
      INSERT INTO public.development_projects
        (id, project_type, display_name, normalized_name)
      VALUES ('00000000-0000-0000-0000-000000000011', 'apartment_community', 'Project A', 'project a');
      INSERT INTO public.properties
        (id, property_type_code, display_name, normalized_name, development_project_id)
      VALUES ('${propertyId}', 'apartment_flat', 'Flat 1201', 'flat 1201', '00000000-0000-0000-0000-000000000011');
      INSERT INTO public.property_assignments (auth_user_id, property_id) VALUES
        ('${callerId}', '${propertyId}'), ('${thirdPartyId}', '${propertyId}');
      INSERT INTO public.parties (id, party_type, canonical_name, normalized_name)
      VALUES ('00000000-0000-0000-0000-000000000012', 'person', 'Owner One', 'owner one');
      INSERT INTO public.crm_contacts (id, display_name)
      VALUES ('00000000-0000-0000-0000-000000000013', 'Owner One Contact');
      INSERT INTO public.crm_contact_methods
        (id, contact_id, method_type, raw_value, normalized_value, consent_status)
      VALUES ('${contactMethodId}', '00000000-0000-0000-0000-000000000013', 'mobile', '+91 90000 00000', '+919000000000', 'unknown');
      INSERT INTO public.contact_method_sources
        (contact_method_id, source_name, source_reference, verification_status)
      VALUES ('${contactMethodId}', 'broker referral', 'ref-2026-10-5', 'candidate');
      INSERT INTO public.property_contact_matches
        (id, property_id, contact_method_id, party_id, match_status, match_method, confidence, source_reference)
      VALUES ('${propertyContactMatchId}', '${propertyId}', '${contactMethodId}', '00000000-0000-0000-0000-000000000012', 'candidate', 'external_source', 0.7000, 'ref-2026-10-5');
      INSERT INTO public.owner_intents
        (id, property_contact_match_id, intent_type, workflow_status, expected_amount, rent_period)
      VALUES
        ('${saleIntentId}', '${propertyContactMatchId}', 'sale', 'queued', 15000000, NULL),
        ('${rentIntentId}', '${propertyContactMatchId}', 'rent', 'queued', 55000, 'month');
    `);

    await assumeUser(database, callerId);
    const sourcedNumbers = await database.query(
      `SELECT source_name, verification_status, captured_by FROM public.contact_method_sources
       WHERE contact_method_id = $1`,
      [contactMethodId],
    );
    assert.deepEqual(sourcedNumbers.rows, [{
      source_name: 'broker referral',
      verification_status: 'candidate',
      captured_by: callerId,
    }]);

    const candidateIntents = await database.query(
      `SELECT intent_type, contact_match_status
       FROM public.property_owner_intents_read WHERE property_id = $1`,
      [propertyId],
    );
    assert.ok(candidateIntents.rows.every((intent) => intent.contact_match_status === 'candidate'));

    await database.query(
      `UPDATE public.property_contact_matches
       SET match_status = 'confirmed', match_method = 'owner_call', confidence = 1
        WHERE id = $1`,
      [propertyContactMatchId],
    );
    const confirmedMatch = await database.query(
      `SELECT match_status, reviewed_by FROM public.property_contact_matches WHERE id = $1`,
      [propertyContactMatchId],
    );
    assert.deepEqual(confirmedMatch.rows[0], { match_status: 'confirmed', reviewed_by: callerId });
    await database.query(
      `UPDATE public.owner_intents
       SET workflow_status = 'interested'
        WHERE id = $1`,
      [saleIntentId],
    );
    await database.query(
      `INSERT INTO public.owner_intent_call_attempts
        (owner_intent_id, call_outcome, notes)
       VALUES ($1, 'no_answer', 'First call; schedule another attempt')`,
      [rentIntentId],
    );
    await database.query(
      `UPDATE public.owner_intents SET workflow_status = 'callback_requested'
       WHERE id = $1`,
      [rentIntentId],
    );

    const intents = await database.query(
      `SELECT intent_type, workflow_status, expected_amount, rent_period
       FROM public.property_owner_intents_read
       WHERE property_id = $1 ORDER BY intent_type`,
      [propertyId],
    );
    assert.deepEqual(intents.rows, [
      { intent_type: 'rent', workflow_status: 'callback_requested', expected_amount: '55000.00', rent_period: 'month' },
      { intent_type: 'sale', workflow_status: 'interested', expected_amount: '15000000.00', rent_period: null },
    ]);

    const rentCalls = await database.query(
      `SELECT attempted_by, call_outcome FROM public.owner_intent_call_attempts
       WHERE owner_intent_id = $1`,
      [rentIntentId],
    );
    assert.deepEqual(rentCalls.rows, [{ attempted_by: callerId, call_outcome: 'no_answer' }]);

    const statusHistory = await database.query(
      `SELECT from_status, to_status, actor_user_id
       FROM public.owner_intent_status_history
       WHERE owner_intent_id = $1 ORDER BY event_sequence`,
      [saleIntentId],
    );
    assert.deepEqual(statusHistory.rows.map((row) => row.to_status), ['queued', 'interested']);
    assert.equal(statusHistory.rows[1].actor_user_id, callerId);

    const attribution = await database.query(
      `SELECT intent_confirmed_at, confirmed_by
       FROM public.owner_intents WHERE id = $1`,
      [saleIntentId],
    );
    assert.ok(attribution.rows[0].intent_confirmed_at);
    assert.equal(attribution.rows[0].confirmed_by, callerId);

    await assert.rejects(
      database.query(
        'DELETE FROM public.owner_intent_call_attempts WHERE owner_intent_id = $1',
        [rentIntentId],
      ),
      /permission denied for table owner_intent_call_attempts/,
    );
    await database.query('RESET ROLE');
    await assert.rejects(
      database.query(
        'DELETE FROM public.owner_intent_call_attempts WHERE owner_intent_id = $1',
        [rentIntentId],
      ),
      /owner intent history is append-only/,
    );

    await assumeUser(database, otherCallerId);
    const unassignedRead = await database.query(
      'SELECT id FROM public.owner_intents WHERE id = $1',
      [saleIntentId],
    );
    assert.equal(unassignedRead.rows.length, 0);
    await database.query('RESET ROLE');

    await assumeUser(database, thirdPartyId);
    const thirdPartyRead = await database.query(
      'SELECT owner_intent_id FROM public.property_owner_intents_read',
    );
    assert.equal(thirdPartyRead.rows.length, 0);
    await database.query('RESET ROLE');

    await assert.rejects(
      database.query(
        `INSERT INTO public.owner_intents
          (property_contact_match_id, intent_type, cycle_number, workflow_status)
         VALUES ($1, 'sale', 1, 'queued')`,
        [propertyContactMatchId],
      ),
    );
  } finally {
    await database.close();
  }
});