CREATE TABLE public.registration_schedule_property_matches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  registration_schedule_observation_id uuid NOT NULL REFERENCES public.registration_schedule_observations(id) ON DELETE RESTRICT,
  property_id uuid NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
  match_method text NOT NULL CHECK (match_method IN ('source_identifier', 'normalized_text', 'manual_review')),
  match_status text NOT NULL DEFAULT 'pending' CHECK (match_status IN ('pending', 'accepted', 'rejected')),
  confidence numeric(5, 4) CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1),
  source_reference text,
  reviewed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE NULLS NOT DISTINCT (
    registration_schedule_observation_id,
    property_id,
    source_reference
  )
);

CREATE INDEX schedule_property_matches_property_idx
  ON public.registration_schedule_property_matches (property_id, match_status);

CREATE INDEX schedule_property_matches_review_idx
  ON public.registration_schedule_property_matches (match_status, confidence);