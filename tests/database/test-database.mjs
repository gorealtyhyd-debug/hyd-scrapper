import { readdir, readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { PGlite } from '@electric-sql/pglite';

const migrationsPath = fileURLToPath(
  new URL('../../supabase/migrations/', import.meta.url),
);

export async function createTestDatabase() {
  const database = new PGlite();

  try {
    await database.exec(`
      CREATE SCHEMA auth;
      CREATE ROLE anon NOLOGIN;
      CREATE ROLE authenticated NOLOGIN;
      GRANT USAGE ON SCHEMA public, auth TO authenticated;
      GRANT USAGE ON SCHEMA public, auth TO anon;
      CREATE TABLE auth.users (id uuid PRIMARY KEY);
      CREATE FUNCTION auth.uid()
      RETURNS uuid
      LANGUAGE sql
      STABLE
      AS $$
        SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
      $$;
    `);

    const migrationFiles = (await readdir(migrationsPath))
      .filter((file) => file.endsWith('.sql'))
      .sort();

    for (const migrationFile of migrationFiles) {
      await database.exec(await readFile(`${migrationsPath}/${migrationFile}`, 'utf8'));
    }

    return database;
  } catch (error) {
    await database.close();
    throw error;
  }
}