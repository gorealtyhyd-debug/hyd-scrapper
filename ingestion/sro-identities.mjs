function requiredPart(value, fieldName) {
  const normalized = String(value ?? '').trim();
  if (!normalized) {
    throw new TypeError(`SRO identity requires ${fieldName}`);
  }
  return normalized;
}

function documentParts(record) {
  return [
    requiredPart(record.sro_code, 'sro_code'),
    requiredPart(record.registration_year, 'registration_year'),
    String(record.book_no ?? '').trim(),
    requiredPart(record.document_no, 'document_no'),
  ];
}

export function sroDocumentIdentity(record) {
  return JSON.stringify(documentParts(record));
}

export function sroScheduleIdentity(record) {
  const scheduleNumber = requiredPart(record.schedule_no, 'schedule_no');
  return JSON.stringify([...documentParts(record), scheduleNumber]);
}