local cpu = require("script.cpu")

-- Re-attach the cpu module metatable to every stored CPU object.
-- Factorio serialises storage as plain tables — metatables are not saved.
-- This must be called in both on_load (normal resume) and on_configuration_changed
-- (mod update), otherwise all cpu methods are nil after a load.
local function reattach_metatables()
    storage.analytical_combinators = storage.analytical_combinators or {}
    for _, data in pairs(storage.analytical_combinators) do
        if data.cpu then
            setmetatable(data.cpu, cpu)
            -- Backfill input_signals for saves predating 0.7.0
            if not data.cpu.input_signals then
                data.cpu.input_signals = { red = {}, green = {} }
            end
            -- Compile the program if this save predates 0.8.20 (no compiled field)
            data.cpu:ensure_compiled()
        end
    end
end

function ac_dev_mode()
	local freeplay = remote.interfaces["freeplay"]
	if freeplay then -- Disable freeplay popup-message
		if freeplay["set_skip_intro"] then
			remote.call("freeplay", "set_skip_intro", true)
		end
		if freeplay["set_disable_crashsite"] then
			remote.call("freeplay", "set_disable_crashsite", true)
		end
	end
	remote.call("freeplay", "set_created_items", {
		["analytical-combinator"] = 5,
		["constant-combinator"] = 5,
		["selector-combinator"] = 5,
		["medium-electric-pole"] = 10,
		["power-armor"] = 1,
		["personal-roboport-equipment"] = 1,
		["fission-reactor-equipment"] = 1,
		["construction-robot"] = 10,
	})
end

script.on_init(function()
	if settings.startup["analytical-combinator-dev-mode"].value then
		ac_dev_mode()
	end
	storage.analytical_combinators = {}
end)

script.on_load(function()
	reattach_metatables()
end)

script.on_configuration_changed(function()
	reattach_metatables()
end)

require("script.gui")
require("script.events")
