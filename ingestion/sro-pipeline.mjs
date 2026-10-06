import { importSroRows } from './sro-importer.mjs';
import { promoteSroObservations } from './sro-promoter.mjs';

export async function ingestAndPromoteSroRows(client, rows, options) {
  const importResult = await importSroRows(client, rows, options);
  const observations = await client.query(
    `SELECT DISTINCT source_observation_id
     FROM public.source_observation_sightings
     WHERE import_run_id = $1
     ORDER BY source_observation_id`,
    [importResult.importRunId],
  );
  const promotionResult = await promoteSroObservations(
    client,
    observations.rows.map((row) => row.source_observation_id),
  );

  return { ...importResult, promotedCount: promotionResult.promotedCount };
}