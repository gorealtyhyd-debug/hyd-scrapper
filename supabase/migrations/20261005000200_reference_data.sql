CREATE TABLE IF NOT EXISTS public.source_systems (
  code text PRIMARY KEY CHECK (code ~ '^[a-z][a-z0-9_]*$'),
  label text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.property_types (
  code text PRIMARY KEY CHECK (code ~ '^[a-z][a-z0-9_]*$'),
  label text NOT NULL,
  is_initial_listing_type boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.document_types (
  code text PRIMARY KEY CHECK (code ~ '^[a-z][a-z0-9_]*$'),
  label text NOT NULL,
  is_sale_event boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.listing_types (
  code text PRIMARY KEY CHECK (code ~ '^[a-z][a-z0-9_]*$'),
  label text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.listing_statuses (
  code text PRIMARY KEY CHECK (code ~ '^[a-z][a-z0-9_]*$'),
  label text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.party_roles (
  code text PRIMARY KEY CHECK (code ~ '^[A-Z][A-Z0-9_]*$'),
  label text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.lead_statuses (
  code text PRIMARY KEY CHECK (code ~ '^[a-z][a-z0-9_]*$'),
  label text NOT NULL,
  is_terminal boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.access_roles (
  code text PRIMARY KEY CHECK (code ~ '^[a-z][a-z0-9_]*$'),
  label text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.source_systems (code, label) VALUES
  ('telangana_sro', 'Telangana registration department SRO'),
  ('telangana_rera', 'Telangana RERA')
ON CONFLICT (code) DO UPDATE SET label = EXCLUDED.label;

INSERT INTO public.property_types (code, label, is_initial_listing_type) VALUES
  ('apartment_flat', 'Apartment or flat', true),
  ('villa', 'Villa', true),
  ('open_plot', 'Open plot', true),
  ('house', 'House', false),
  ('row_house', 'Row house', false),
  ('commercial', 'Commercial property', false),
  ('agricultural_land', 'Agricultural land', false),
  ('unknown', 'Unclassified source property', false)
ON CONFLICT (code) DO UPDATE
SET label = EXCLUDED.label,
    is_initial_listing_type = EXCLUDED.is_initial_listing_type;

INSERT INTO public.document_types (code, label, is_sale_event) VALUES
  ('sale_deed', 'Sale deed', true),
  ('mortgage_deed', 'Mortgage deed', false),
  ('mortgage_without_possession', 'Mortgage without possession', false),
  ('deposit_title_deeds', 'Deposit of title deeds', false),
  ('mortgage_release', 'Release of mortgage rights', false),
  ('development_agreement', 'Development agreement', false),
  ('gift_deed', 'Gift deed', false),
  ('family_release', 'Release among family members', false),
  ('lease_deed', 'Lease deed', false),
  ('general_power_of_attorney', 'General power of attorney', false),
  ('rectification', 'Rectification deed', false),
  ('cancellation', 'Cancellation deed', false),
  ('other', 'Other or unclassified document', false)
ON CONFLICT (code) DO UPDATE
SET label = EXCLUDED.label,
    is_sale_event = EXCLUDED.is_sale_event;

INSERT INTO public.listing_types (code, label) VALUES
  ('sale', 'For sale'),
  ('rent', 'For rent')
ON CONFLICT (code) DO UPDATE SET label = EXCLUDED.label;

INSERT INTO public.listing_statuses (code, label, is_active) VALUES
  ('draft', 'Draft', true),
  ('active', 'Active', true),
  ('paused', 'Paused', true),
  ('withdrawn', 'Withdrawn', false),
  ('expired', 'Expired', false),
  ('closed', 'Closed', false)
ON CONFLICT (code) DO UPDATE
SET label = EXCLUDED.label,
    is_active = EXCLUDED.is_active;

INSERT INTO public.party_roles (code, label) VALUES
  ('EX', 'Executant'),
  ('CL', 'Claimant'),
  ('MR', 'Mortgagor'),
  ('ME', 'Mortgagee'),
  ('RE', 'Releasee'),
  ('RR', 'Releasor'),
  ('DE', 'Donor'),
  ('DR', 'Donee'),
  ('LR', 'Lessor'),
  ('LE', 'Lessee'),
  ('PL', 'Principal'),
  ('AY', 'Attorney'),
  ('OTHER', 'Other recorded role')
ON CONFLICT (code) DO UPDATE SET label = EXCLUDED.label;

INSERT INTO public.lead_statuses (code, label, is_terminal) VALUES
  ('pending', 'Pending', false),
  ('resale', 'Resale', false),
  ('rent', 'Rent', false),
  ('own', 'Own', false),
  ('undecided', 'Undecided', false),
  ('rejected', 'Rejected', true),
  ('inactive', 'Inactive', true)
ON CONFLICT (code) DO UPDATE
SET label = EXCLUDED.label,
    is_terminal = EXCLUDED.is_terminal;

INSERT INTO public.access_roles (code, label) VALUES
  ('admin', 'Administrator'),
  ('telecaller', 'Telecaller'),
  ('sales_representative', 'Sales representative'),
  ('third_party', 'Third party')
ON CONFLICT (code) DO UPDATE SET label = EXCLUDED.label;