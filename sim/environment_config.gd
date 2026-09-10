class_name EnvironmentConfig
extends RefCounted

# All values in this file are dimensionless gameplay assumptions. They are not
# published physical measurements and must not be presented as such.
const RULESET_ID := "tile-environment-v1"
const AMBIENT_TEMPERATURE := 200
const FREEZING_TEMPERATURE := 0
const MELTING_TEMPERATURE := 30
const BOILING_TEMPERATURE := 1000
const CONDENSATION_TEMPERATURE := 850
const MAX_TEMPERATURE := 4000
const MAX_MASS := 1000
const DEFAULT_GAS_AMOUNT := 500
const DEFAULT_EFFECTIVE_VOLUME := 1000
const FLOW_DIVISOR := 4
const HEAT_FLOW_DIVISOR := 16
const PHASE_CHANGE_RATE := 80
const GAS_LOSS_AT_OPEN_EDGE := 20
const HEAT_LOSS_AT_OPEN_EDGE := 8
const FIRE_HEAT_PER_INTENSITY := 3
const FIRE_FUEL_USE_DIVISOR := 10
const OIL_BURN_RATE := 60
const SMOKE_PER_FUEL := 2
const FLAMMABLE_GAS_IGNITION := 120
const PRESSURE_SCALE := 200
const RUPTURE_PRESSURE := 1800
const EQUILIBRIUM_EPSILON := 2
const EXPLOSION_POWER_LOSS_PER_TILE := 20
const COVER_POWER_LOSS := 25
const MAX_EXPLOSION_CHAIN := 128


static func pressure_for(tile) -> int:
	var gas_total: int = tile.gas_amount + tile.smoke_amount \
		+ tile.steam_amount + tile.flammable_gas_amount
	var absolute_temperature := maxi(1, tile.temperature + 1000)
	return gas_total * absolute_temperature * PRESSURE_SCALE \
		/ (DEFAULT_EFFECTIVE_VOLUME * 1000)

