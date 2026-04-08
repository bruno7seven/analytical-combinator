local cpu = require("script.cpu")

-- Reattach metatables to cpu objects after load (Factorio does not persist them).
-- Also rebuilds the compiled program cache which lives outside storage entirely,
-- so it is always absent after a load and must be reconstructed from self.memory.
-- This function only reads storage (via data.cpu.memory); it never writes to it,
-- making it safe to call from on_load.
local function reattach_metatables()
    storage.analytical_combinators = storage.analytical_combinators or {}
    for unit_number, data in pairs(storage.analytical_combinators) do
        if data.cpu then
            setmetatable(data.cpu, cpu)
            -- Rebuild the compiled program from self.memory.
            -- Uses tostring(cpu) as cache key — no fields written to storage.
            data.cpu:rebuild_compiled()
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
