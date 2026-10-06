import assert from 'node:assert/strict';
import { test } from 'node:test';
import { sroDocumentIdentity, sroScheduleIdentity } from '../../ingestion/sro-identities.mjs';

const baseRecord = {
  sro_code: '1522',
  registration_year: '2026',
  book_no: '1',
  document_no: '00125',
  schedule_no: '1',
};

test('document identity is independent of schedule identity', () => {
  const secondSchedule = { ...baseRecord, schedule_no: '2' };

  assert.equal(sroDocumentIdentity(baseRecord), sroDocumentIdentity(secondSchedule));
  assert.notEqual(sroScheduleIdentity(baseRecord), sroScheduleIdentity(secondSchedule));
});

test('document identity is scoped by SRO and preserves source identifier text', () => {
  assert.notEqual(
    sroDocumentIdentity(baseRecord),
    sroDocumentIdentity({ ...baseRecord, sro_code: '1523' }),
  );
  assert.notEqual(
    sroDocumentIdentity(baseRecord),
    sroDocumentIdentity({ ...baseRecord, document_no: '125' }),
  );
  assert.equal(
    sroDocumentIdentity({ ...baseRecord, sro_code: ' 1522 ' }),
    sroDocumentIdentity(baseRecord),
  );
});

test('identity rejects records missing required source identifiers', () => {
  assert.throws(() => sroDocumentIdentity({ ...baseRecord, document_no: '' }), /document_no/);
  assert.throws(() => sroScheduleIdentity({ ...baseRecord, schedule_no: '' }), /schedule_no/);
});