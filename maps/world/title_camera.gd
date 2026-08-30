class_name TitleCamera
extends RefCounted

## THE INTRO'S CAMERA PATH (owner 2026-08-30: "I love the intro. Could it be
## looped in some way?").
##
## A slow closed figure-eight over the whale pod. Closed is the whole point: the
## first cut drifted one way forever, which sails off into empty sky and leaves
## the intro looking at nothing a minute after boot. This returns to where it
## started every TITLE-period, so a title screen left running all night is still
## looking at whales.
##
## Its own tiny class, and pure, for one specific reason: `world.gd` has no
## `class_name` and it references the `Net` autoload, so a test that named it as
## a type would compile it before the autoloads exist (CODEMAP §4). A pure
## RefCounted with no autoload in it is reachable from the suite for free.

## Seconds for one full pass. Long enough that the motion reads as drift.
const PERIOD := 46.0
## Half the horizontal travel, px at scale 1.
const SWEEP := 1100.0
## Half the vertical travel, px at scale 1. Much smaller than the sweep — the
## sky is wide, not tall, and a camera that bobs as far as it pans reads as a
## boat rather than a establishing shot.
const RISE := 300.0
## How fast the anchor eases toward the live pod centre, per physics frame.
## Whales roam, so a centroid sampled once at boot is stale within a minute.
const ANCHOR_EASE := 0.01


## The offset from the anchor at time `t`, in px at scale 1. x sweeps once per
## PERIOD and y twice, which draws a figure-eight and closes exactly.
static func offset(t: float) -> Vector2:
	var a := TAU * t / PERIOD
	return Vector2(sin(a) * SWEEP, sin(a * 2.0) * RISE)
