-- Pitch type clustering data: one row per pitcher per pitch type (50+ pitches)
-- Includes the 4 shape measurements used for clustering, plus Statcast's label
-- at two levels (family and pitch label), which are only used to score the clusters afterward
-- Built from pitch_summary (all pitchers), where junk pitch types are already removed
-- and lefties are mirrored so arm side movement is positive for everyone

SELECT pitcher,
       player_name,
       p_throws,
       pitch_type,
       pitches,

       -- The 4 clustering measurements
       velo,
       ivb,
       hb,
       spin,

       -- Family label (used to score k = 3)
       CASE
         WHEN pitch_type IN ('FF', 'SI', 'FC') THEN 'Fastball'
         WHEN pitch_type IN ('CH', 'FS', 'FO') THEN 'Offspeed'
         ELSE 'Breaking'
       END AS family,

       -- Pitch label (used to score k = 7 and k = 8)
       CASE
         WHEN pitch_type = 'FF'                THEN 'Four Seamer'
         WHEN pitch_type = 'SI'                THEN 'Sinker'
         WHEN pitch_type = 'FC'                THEN 'Cutter'
         WHEN pitch_type = 'CH'                THEN 'Changeup'
         WHEN pitch_type IN ('FS', 'FO')       THEN 'Splitter'
         WHEN pitch_type IN ('CU', 'KC', 'CS') THEN 'Curveball'
         WHEN pitch_type IN ('SL', 'SV')       THEN 'Slider'
         WHEN pitch_type = 'ST'                THEN 'Sweeper'
       END AS pitch_label

FROM pitch_summary
WHERE pitches >= 50
  AND spin IS NOT NULL
  
ORDER BY pitcher, pitch_type