-- The analytical combinator is based on the decider combinator.
-- We replace all six comparison-operator symbol sprites with our custom
-- microchip display image so the entity is visually distinct in-world.

local analytical_combinator =
    flib.copy_prototype(data.raw["decider-combinator"]["decider-combinator"], "analytical-combinator")

-- Custom display sprite: 30×22 px microchip symbol (amber/yellow on dark screen).
-- We inherit scale and shift from the base decider combinator's equal_symbol_sprites
-- so the image sits exactly where the '=' symbol normally appears.
local chip_display = {
    north = {
        filename = "__analytical-combinator__/graphics/entities/ac-display.png",
        width    = 30,
        height   = 22,
        scale    = analytical_combinator.equal_symbol_sprites.north.scale,
        shift    = analytical_combinator.equal_symbol_sprites.north.shift,
    },
    east = {
        filename = "__analytical-combinator__/graphics/entities/ac-display.png",
        width    = 30,
        height   = 22,
        scale    = analytical_combinator.equal_symbol_sprites.east.scale,
        shift    = analytical_combinator.equal_symbol_sprites.east.shift,
    },
    south = {
        filename = "__analytical-combinator__/graphics/entities/ac-display.png",
        width    = 30,
        height   = 22,
        scale    = analytical_combinator.equal_symbol_sprites.south.scale,
        shift    = analytical_combinator.equal_symbol_sprites.south.shift,
    },
    west = {
        filename = "__analytical-combinator__/graphics/entities/ac-display.png",
        width    = 30,
        height   = 22,
        scale    = analytical_combinator.equal_symbol_sprites.west.scale,
        shift    = analytical_combinator.equal_symbol_sprites.west.shift,
    },
}

-- Replace every comparison-operator symbol with our chip display.
-- The decider combinator has six: =, >, <, ≠, ≥, ≤
analytical_combinator.equal_symbol_sprites           = chip_display
analytical_combinator.greater_symbol_sprites         = chip_display
analytical_combinator.less_symbol_sprites            = chip_display
analytical_combinator.not_equal_symbol_sprites       = chip_display
analytical_combinator.greater_or_equal_symbol_sprites = chip_display
analytical_combinator.less_or_equal_symbol_sprites   = chip_display

-- Override the icon used in the entity tooltip / map view
analytical_combinator.icon = "__analytical-combinator__/graphics/icons/analytical-combinator.png"

data:extend({ analytical_combinator })
