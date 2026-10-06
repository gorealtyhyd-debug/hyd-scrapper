import { readFile } from 'node:fs/promises';
import { Pool } from 'pg';
import { parseSroCsv } from '../ingestion/sro-importer.mjs';
import { ingestAndPromoteSroRows } from '../ingestion/sro-pipeline.mjs';

function argumentValue(name) {
  const index = process.argv.indexOf(name);
  return index < 0 ? null : process.argv[index + 1] ?? null;
}

const filePath = argumentValue('--file');
const runKind = argumentValue('--mode');
const databaseUrl = process.env.DATABASE_URL;

if (!filePath || !runKind || !databaseUrl) {
  throw new Error('Usage: node scripts/import-sro-csv.mjs --file <path> --mode <historical_backfill|daily|replay|manual> with DATABASE_URL set');
}

const rows = parseSroCsv(await readFile(filePath, 'utf8'));
const pool = new Pool({ connectionString: databaseUrl });
const client = await pool.connect();

try {
  const result = await ingestAndPromoteSroRows(client, rows, {
    runKind,
    parserVersion: '1.0.0',
  });
  console.log(JSON.stringify(result));
} finally {
  client.release();
  await pool.end();
}