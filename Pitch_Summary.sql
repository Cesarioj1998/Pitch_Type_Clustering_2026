-- One row per pitcher per pitch type: usage, shape, release, and results
-- Built from pitches_clean, so junk pitches are already removed and lefties are mirrored

CREATE OR REPLACE TABLE pitch_summary AS

WITH base AS (
  SELECT
    pitcher,
    player_name,
    p_throws,
    pitch_type,
    pitch_group,
    COUNT(*) AS pitches,

    -- Pitch shape
    AVG(release_speed)     AS velo,
    AVG(release_spin_rate) AS spin,
    AVG(ivb_in)            AS ivb,
    AVG(hb_arm_in)         AS hb,

    -- Spin axis averaged around the circle (so 350 and 10 average to 0, not 180)
    AVG(SIN(RADIANS(spin_axis_adj))) AS axis_sin,
    AVG(COS(RADIANS(spin_axis_adj))) AS axis_cos,

    -- Release
    AVG(release_x_arm)     AS release_side,
    AVG(release_pos_z)     AS release_height,
    AVG(release_extension) AS extension,
    AVG(arm_angle)         AS arm_angle,

    -- Whiffs = swings and misses (bunts left out)
    SUM(CASE WHEN description IN ('swinging_strike', 'swinging_strike_blocked')
             THEN 1 ELSE 0 END) AS whiffs,

    -- Swings = whiffs plus fouls plus balls in play
    SUM(CASE WHEN description IN ('swinging_strike', 'swinging_strike_blocked',
                                  'foul', 'foul_tip', 'hit_into_play')
             THEN 1 ELSE 0 END) AS swings,

    SUM(CASE WHEN description = 'called_strike' THEN 1 ELSE 0 END) AS called_strikes,

    -- Zones 11 to 14 are outside the strike zone
    SUM(CASE WHEN zone > 9 THEN 1 ELSE 0 END) AS out_of_zone,

    -- Chases = swings on pitches outside the zone
    SUM(CASE WHEN zone > 9
              AND description IN ('swinging_strike', 'swinging_strike_blocked',
                                  'foul', 'foul_tip', 'hit_into_play')
             THEN 1 ELSE 0 END) AS chases,

    -- Run value flipped so positive = good for the pitcher
    -SUM(delta_run_exp) AS run_value

  FROM pitches_clean
  GROUP BY pitcher, player_name, p_throws, pitch_type, pitch_group
)

SELECT
  pitcher,
  player_name,
  p_throws,
  pitch_type,
  pitch_group,
  pitches,

  -- Usage: this pitch type's share of the pitcher's total pitches
  ROUND(pitches * 100.0 / SUM(pitches) OVER (PARTITION BY pitcher), 1) AS usage_pct,

  ROUND(velo, 1) AS velo,
  ROUND(spin, 0) AS spin,
  ROUND(ivb, 1)  AS ivb,
  ROUND(hb, 1)   AS hb,

  -- Convert the circular average back to degrees between 0 and 360
  ROUND(CASE
          WHEN DEGREES(ATAN2(axis_sin, axis_cos)) < 0
          THEN DEGREES(ATAN2(axis_sin, axis_cos)) + 360
          ELSE DEGREES(ATAN2(axis_sin, axis_cos))
        END, 0) AS spin_axis,

  ROUND(release_side, 2)   AS release_side,
  ROUND(release_height, 2) AS release_height,
  ROUND(extension, 2)      AS extension,
  ROUND(arm_angle, 1)      AS arm_angle,

  -- Result rates (NULLIF avoids dividing by zero for pitches with no swings)
  ROUND(whiffs * 100.0 / NULLIF(swings, 0), 1)               AS whiff_pct,
  ROUND((called_strikes + whiffs) * 100.0 / pitches, 1)      AS csw_pct,
  ROUND(chases * 100.0 / NULLIF(out_of_zone, 0), 1)          AS chase_pct,
  ROUND(run_value * 100.0 / pitches, 2)                      AS rv_per100

FROM base

