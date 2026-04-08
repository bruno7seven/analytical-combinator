local cpu = require("cpu")

-- ── Output helpers ────────────────────────────────────────────────────────────
-- LuaDeciderCombinatorControlBehavior uses a parameters table with two arrays:
--   conditions :: array[DeciderCombinatorCondition]
--   outputs    :: array[DeciderCombinatorOutput]
--
-- To make the combinator unconditionally emit our chosen signals we set:
--   - one always-true condition  (1 = 1)
--   - one output entry per active o-register  (signal, constant = count)
--
-- Setting behavior.parameters = nil silently clears everything.

-- Always-true condition using two numeric constants (0 = 0).
-- This references no signals at all, so it never shows up as an output
-- signal in alt-mode or on the circuit network. Any condition with
-- first_signal set to signal-everything leaks that special aggregate
-- signal visually and behaviourally onto the output wire.
local ALWAYS_TRUE_CONDITION = {
    comparator      = "=",
    first_constant  = 0,
    second_constant = 0,
}

local function clear_outputs(entity)
    local behavior = entity.get_control_behavior()
    if behavior then
        behavior.parameters = nil
    end
end

-- Resolve a signal name to its correct SignalID type by checking all three
-- prototype dictionaries in order: virtual signals first (most likely for
-- WSIG usage with signal-red, signal-A etc.), then items, then fluids.
-- Returns nil if the name is not a valid signal in any category.
local function resolve_signal_id(name)
    if prototypes.virtual_signal[name] then
        return { type = "virtual", name = name }
    elseif prototypes.item[name] then
        return { type = "item", name = name, quality = "normal" }
    elseif prototypes.fluid[name] then
        return { type = "fluid", name = name }
    end
    return nil
end

local function write_outputs(entity, cpu_state)
    local behavior = entity.get_control_behavior()
    if not behavior then return end

    -- Collect active output registers, resolving each signal name to its
    -- correct type (virtual, item, or fluid) at emit time.
    local outputs = {}
    for i = 0, 3 do
        local reg = cpu_state:get_register("o" .. i)
        if reg and reg.name ~= nil and reg.count ~= 0 then
            local signal_id = resolve_signal_id(reg.name)
            if signal_id then
                table.insert(outputs, {
                    signal                = signal_id,
                    constant              = reg.count,
                    copy_count_from_input = false,
                })
            end
            -- If signal_id is nil the name is invalid; silently skip it
            -- rather than crashing. The CPU will keep running.
        end
    end

    if #outputs == 0 then
        behavior.parameters = nil
        return
    end

    behavior.parameters = {
        conditions = { ALWAYS_TRUE_CONDITION },
        outputs    = outputs,
    }
end

-- ── Entity lifecycle ──────────────────────────────────────────────────────────

local function register_entity(entity, code)
    if entity.name == "analytical-combinator" then
        storage.analytical_combinators[entity.unit_number] = {
            entity           = entity,
            cpu              = cpu.new(code),
            last_process_tick = game.tick,
        }
        clear_outputs(entity)
    end
end

local function get_code_from_tags(tags)
    if tags and tags.analytical_combinator_code then
        return tags.analytical_combinator_code
    end
    return nil
end

script.on_event(defines.events.on_built_entity, function(event)
    register_entity(event.entity, get_code_from_tags(event.tags))
end)
script.on_event(defines.events.on_robot_built_entity, function(event)
    register_entity(event.entity, get_code_from_tags(event.tags))
end)
script.on_event(defines.events.on_entity_cloned, function(event)
    local source = storage.analytical_combinators[event.source.unit_number]
    local code = source and source.cpu:get_code() or nil
    register_entity(event.destination, code)
end)
script.on_event(defines.events.script_raised_built, function(event)
    register_entity(event.entity, get_code_from_tags(event.tags))
end)
script.on_event(defines.events.on_entity_settings_pasted, function(event)
    if event.destination.name == "analytical-combinator" then
        local source = storage.analytical_combinators[event.source.unit_number]
        local code = source and source.cpu:get_code() or nil
        local dest = storage.analytical_combinators[event.destination.unit_number]
        if dest then
            dest.cpu:update_code(code or { "HLT" })
            clear_outputs(event.destination)
        end
    end
end)

script.on_event(defines.events.on_player_setup_blueprint, function(event)
    local player = game.get_player(event.player_index)
    if not player then return end

    local blueprint = player.blueprint_to_setup
    if not blueprint or not blueprint.valid_for_read then
        blueprint = player.cursor_stack
    end
    if not blueprint or not blueprint.valid_for_read then return end

    local mapping = event.mapping.get()
    for blueprint_index, entity in pairs(mapping) do
        if entity.valid and entity.name == "analytical-combinator" then
            local data = storage.analytical_combinators[entity.unit_number]
            if data then
                blueprint.set_blueprint_entity_tag(blueprint_index, "analytical_combinator_code", data.cpu:get_code())
            end
        end
    end
end)

local function cleanup_entity(entity)
    if entity and entity.valid and entity.unit_number then
        storage.analytical_combinators[entity.unit_number] = nil
    end
end

script.on_event(defines.events.on_entity_died, function(event)
    cleanup_entity(event.entity)
end)
script.on_event(defines.events.on_robot_pre_mined, function(event)
    cleanup_entity(event.entity)
end)
script.on_event(defines.events.on_pre_player_mined_item, function(event)
    cleanup_entity(event.entity)
end)

-- ── Signal reading helper ─────────────────────────────────────────────────────

-- Flatten a LuaCircuitNetwork's signals into { [name] = count }
local function read_network_signals(network)
    local result = {}
    if network then
        local signals = network.signals
        if signals then
            for _, entry in pairs(signals) do
                result[entry.signal.name] = (result[entry.signal.name] or 0) + entry.count
            end
        end
    end
    return result
end

-- ── Per-tick update ───────────────────────────────────────────────────────────

script.on_event(defines.events.on_tick, function()
    for unit_number, data in pairs(storage.analytical_combinators) do
        local entity = data.entity

        if not entity.valid then
            storage.analytical_combinators[unit_number] = nil
        else
            data.last_process_tick = game.tick

            -- Feed current input signals into the CPU before stepping,
            -- so RSIGR / RSIGG see the values for this tick.
            local red_network   = entity.get_circuit_network(defines.wire_connector_id.combinator_input_red)
            local green_network = entity.get_circuit_network(defines.wire_connector_id.combinator_input_green)
            data.cpu:set_input_signals(
                read_network_signals(red_network),
                read_network_signals(green_network)
            )

            data.cpu:tick()

            -- Update error display in any open GUI
            if #data.cpu:get_errors() ~= 0 then
                for _, player in pairs(game.players) do
                    local gui_name = "analytical_combinator_gui_" .. entity.unit_number
                    local gui = player.gui.screen[gui_name]
                    if gui and gui.content and gui.content.errors then
                        gui.content.errors.caption = data.cpu:get_errors()[1]
                    end
                end
                goto continue
            end

            -- Update status icon in any open GUI
            for _, player in pairs(game.players) do
                local gui_name = "analytical_combinator_gui_" .. entity.unit_number
                local gui = player.gui.screen[gui_name]
                if gui and gui.content and gui.content.working then
                    local sprite, label
                    if data.cpu:is_halted() then
                        sprite = "utility/status_not_working"
                        label  = "Halted"
                    elseif #data.cpu:get_errors() ~= 0 then
                        sprite = "utility/status_yellow"
                        label  = "Error"
                    else
                        sprite = "utility/status_working"
                        label  = "Working"
                    end
                    gui.content.working.working_icon.sprite = sprite
                    gui.content.working.working_label.caption = label
                end
            end

            -- Update connection label in any open GUI
            local connected_caption = (red_network or green_network)
                and "Connected to circuit network"
                or  "Not connected"

            for _, player in pairs(game.players) do
                local gui_name = "analytical_combinator_gui_" .. entity.unit_number
                local gui = player.gui.screen[gui_name]
                if gui and gui.content
                    and gui.content.connected
                    and gui.content.connected.connected_label
                then
                    gui.content.connected.connected_label.caption = connected_caption
                end
            end

            -- Push o0..o3 to the decider combinator's output network
            write_outputs(entity, data.cpu)
        end
        ::continue::
    end
end)
