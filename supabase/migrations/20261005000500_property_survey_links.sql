CREATE TABLE public.property_survey_identifiers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id uuid NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
  survey_identifier_id uuid NOT NULL REFERENCES public.survey_identifiers(id) ON DELETE RESTRICT,
  match_method text NOT NULL CHECK (match_method IN ('source_identifier', 'normalized_text', 'manual_review')),
  match_status text NOT NULL CHECK (match_status IN ('pending', 'accepted', 'rejected')),
  confidence numeric(5, 4) CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1),
  source_reference text,
  created_at timestamptz NOT NULL DEFAULT now(),
  reviewed_at timestamptz,
  UNIQUE NULLS NOT DISTINCT (property_id, survey_identifier_id, source_reference)
);

CREATE INDEX property_survey_identifiers_survey_idx
  ON public.property_survey_identifiers (survey_identifier_id, match_status);

CREATE INDEX property_survey_identifiers_property_idx
  ON public.property_survey_identifiers (property_id, match_status);