class_name SimNeeds
extends RefCounted

## Response curves: convert a need deficit (0 satisfied .. 1 critical) into
## urgency. Flat while satisfied, steep when critical. The steepness is what
## makes a starving creature unable to think about anything else, without any
## coded priority ladder.


static func urgency(deficit: float, exponent: float) -> float:
	return pow(clampf(deficit, 0.0, 1.0), maxf(exponent, 0.001))
