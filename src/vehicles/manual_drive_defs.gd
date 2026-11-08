class_name ManualDriveDefs
extends RefCounted
## All tuning of manual driving (placeholders) in one place. Design: design/gdd/manual-driving.md.

const SCHEME_JOYSTICK := &"joystick"
const SCHEME_TILT := &"tilt"
const SCHEME_BUTTONS := &"buttons"
const SCHEMES: Array[StringName] = [SCHEME_JOYSTICK, SCHEME_TILT, SCHEME_BUTTONS]
const SCHEME_NAMES := {SCHEME_JOYSTICK: "Джойстик", SCHEME_TILT: "Наклон", SCHEME_BUTTONS: "Кнопки"}
const DEFAULT_SCHEME := SCHEME_JOYSTICK

## --- Input shaping ---
const STICK_DEAD := 0.12             # joystick radial dead zone (fraction of the radius)
const TILT_DEAD_DEG := 4.0           # no reaction inside this angle from the neutral pose
const TILT_STEER_FULL_DEG := 25.0    # full steering at this roll
const TILT_THROTTLE_FULL_DEG := 20.0 # full gas/brake at this pitch
const TILT_SMOOTH := 12.0            # 1/s low-pass of the accelerometer
const TILT_STEER_SIGN := 1.0         # flip if the device reports the opposite axis (verify on a phone)
const TILT_THROTTLE_SIGN := 1.0

## --- Dynamics (same terrain/load/slip/wear model as AI driving; only the controls are new) ---
const ACCEL_TIME := 2.0              # s from 0 to the type's nominal speed
const BRAKE_TIME := 0.8
const COAST_TIME := 2.5              # engine braking with no input
const LOAD_ACCEL_PENALTY := 1.0      # accel divided by (1 + this x load fraction)
const REVERSE_FRAC := 0.4            # reverse top speed (fraction of forward max)
const TURN_RATE := 1.3               # rad/s at full steering
const TURN_FULL_SPEED := 1.5         # m/s from which steering is full
const MAX_FRAME_DT := 0.1            # s, clamp for hitches
const KMH := 3.6

## --- Chase camera ---
const CHASE_DISTANCE := 14.0
const CHASE_AHEAD := 4.0             # m: the camera looks this far ahead of the vehicle
const CHASE_SMOOTHING := 3.5         # 1/s (softer than the RTS camera)

static func scheme_name(s: StringName) -> String:
	return SCHEME_NAMES.get(s, String(s))
