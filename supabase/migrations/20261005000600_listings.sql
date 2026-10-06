CREATE TABLE public.property_listings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id uuid NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
  listing_type_code text NOT NULL REFERENCES public.listing_types(code) ON DELETE RESTRICT,
  listing_status_code text NOT NULL REFERENCES public.listing_statuses(code) ON DELETE RESTRICT,
  source_system_code text REFERENCES public.source_systems(code) ON DELETE RESTRICT,
  source_reference text,
  asking_price numeric(14, 2) CHECK (asking_price IS NULL OR asking_price > 0),
  currency_code text NOT NULL DEFAULT 'INR' CHECK (currency_code ~ '^[A-Z]{3}$'),
  rent_period text CHECK (rent_period IS NULL OR rent_period IN ('day', 'week', 'month', 'year')),
  available_from date,
  published_at timestamptz,
  ended_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK ((listing_type_code = 'rent') OR rent_period IS NULL),
  CHECK (ended_at IS NULL OR published_at IS NULL OR ended_at >= published_at)
);

CREATE UNIQUE INDEX property_listings_source_identity_uq
  ON public.property_listings (source_system_code, source_reference)
  WHERE source_system_code IS NOT NULL AND source_reference IS NOT NULL;

CREATE INDEX property_listings_active_search_idx
  ON public.property_listings (listing_type_code, listing_status_code, property_id);

CREATE TABLE public.property_listing_status_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_sequence bigint GENERATED ALWAYS AS IDENTITY UNIQUE,
  property_listing_id uuid NOT NULL REFERENCES public.property_listings(id) ON DELETE RESTRICT,
  from_status_code text REFERENCES public.listing_statuses(code) ON DELETE RESTRICT,
  to_status_code text NOT NULL REFERENCES public.listing_statuses(code) ON DELETE RESTRICT,
  actor_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reason text,
  event_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX property_listing_status_history_timeline_idx
  ON public.property_listing_status_history (property_listing_id, event_at);

CREATE OR REPLACE FUNCTION public.record_listing_status_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.property_listing_status_history
      (property_listing_id, to_status_code, actor_user_id)
    VALUES (NEW.id, NEW.listing_status_code, auth.uid());
  ELSIF NEW.listing_status_code IS DISTINCT FROM OLD.listing_status_code THEN
    INSERT INTO public.property_listing_status_history
      (property_listing_id, from_status_code, to_status_code, actor_user_id)
    VALUES (NEW.id, OLD.listing_status_code, NEW.listing_status_code, auth.uid());
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER property_listings_record_initial_status
  AFTER INSERT ON public.property_listings
  FOR EACH ROW EXECUTE FUNCTION public.record_listing_status_change();

CREATE TRIGGER property_listings_record_status_change
  AFTER UPDATE OF listing_status_code ON public.property_listings
  FOR EACH ROW EXECUTE FUNCTION public.record_listing_status_change();

CREATE TRIGGER property_listings_updated_at
  BEFORE UPDATE ON public.property_listings
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();