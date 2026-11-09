-- Clean pitch table: drops junk pitch types and untracked pitches,
-- groups pitches into families, converts break to inches,
-- mirrors lefties so arm side is always positive,
-- and calculates vertical approach angle (VAA) at the front of home plate

CREATE OR REPLACE VIEW pitches_clean AS

-- Step 1: filter out junk pitches and find the pitch's forward speed at the plate
-- Statcast gives velocity (vy0) and acceleration (ay) at 50 feet from the plate;
-- the front of the plate is 17 inches (17/12 feet) from the back tip
WITH base AS (
  SELECT *,
         -SQRT(vy0 * vy0 - 2 * ay * (50 - 17.0 / 12)) AS vy_plate
  FROM pitches
  WHERE pitch_type IN ('FF', 'SI', 'FC', 'SL', 'ST', 'SV', 'CU', 'KC', 'CS', 'CH', 'FS', 'FO')
    AND release_speed IS NOT NULL
    AND pfx_x IS NOT NULL
    AND pfx_z IS NOT NULL
)

SELECT *,

  -- Group pitch types into families (slow curve goes with breaking, forkball with offspeed)
  CASE
    WHEN pitch_type IN ('FF', 'SI', 'FC') THEN 'Fastball'
    WHEN pitch_type IN ('SL', 'ST', 'SV', 'CU', 'KC', 'CS') THEN 'Breaking'
    WHEN pitch_type IN ('CH', 'FS', 'FO') THEN 'Offspeed'
  END AS pitch_group,

  -- Induced vertical break in inches (pfx_z is in feet)
  pfx_z * 12 AS ivb_in,

  -- Horizontal break in inches, arm side positive for both righties and lefties
  CASE WHEN p_throws = 'R' THEN -pfx_x * 12 ELSE pfx_x * 12 END AS hb_arm_in,

  -- Release side in feet, arm side positive for both righties and lefties
  CASE WHEN p_throws = 'R' THEN -release_pos_x ELSE release_pos_x END AS release_x_arm,

  -- Spin axis mirrored for lefties so they read like righties
  CASE WHEN p_throws = 'L' THEN 360 - spin_axis ELSE spin_axis END AS spin_axis_adj,

  -- Vertical approach angle in degrees: the angle of the pitch's path as it reaches the plate
  -- Downward speed at the plate = starting downward speed + downward acceleration x travel time
  -- Closer to 0 = flatter (harder to get on top of up in the zone); more negative = steeper
  -DEGREES(ATAN(
    (vz0 + az * ((vy_plate - vy0) / ay)) / vy_plate
  )) AS vaa

FROM base
