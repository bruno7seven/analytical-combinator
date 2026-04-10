local cpu = require("script.cpu")

-- Reattach the cpu module metatable to every stored cpu object after load.
-- Factorio does not persist metatables through the save/load cycle.
-- self.tick_ndx (0 or 1) is an integer stored in storage and persists
-- correctly — no write needed here. Combinators from pre-tick_ndx saves
-- will have tick_ndx = nil. cpu:tick() uses (self.tick_ndx or 0) + 1
-- so nil is treated as 0, calling boot() on the first tick.
local function reattach_metatables()
    storage.analytical_combinators = storage.analytical_combinators or {}
    for _, data in pairs(storage.analytical_combinators) do
        if data.cpu then
            setmetatable(data.cpu, cpu)
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
