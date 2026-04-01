local module = {}
module.__index = module

-- LuaJIT (Factorio's runtime) implements Lua 5.1 — the bitwise operators
-- &, |, ~, <<, >> do not exist. Use the bit library instead.
-- LuaJIT ships "bit" built-in; standard Lua 5.2 has "bit32". Try both.
local _bitlib = bit32 or bit
local _band    = _bitlib.band
local _bor     = _bitlib.bor
local _bxor    = _bitlib.bxor
local _bnot    = _bitlib.bnot
local _lshift  = _bitlib.lshift
local _rshift  = _bitlib.rshift    -- logical (zero-fill)
local _arshift = _bitlib.arshift   -- arithmetic (sign-extend)

function module.parse_labels(code)
    local label_pattern = "^%s*([%w_][%w_]*):.*$"
    local labels = {}
    for i, line in ipairs(code) do
        if line:match(label_pattern) then
            local label_name = module.extract_label_name(line)
            labels[label_name] = i
        end
    end
    return labels
end

function module.extract_label_name(line)
    local label_name_pattern = "^%s*([%w_][%w_]*):.*$"
    return line:match(label_name_pattern)
end

function module.new(code)
    local cpuClass = setmetatable({}, module)

    cpuClass.status = {
        is_halted = false,
        jump_executed = false,
        error = false,
    }
    cpuClass.registers = {}
    for i = 0, 31 do
        cpuClass.registers["x" .. i] = 0
    end
    for i = 0, 3 do
        cpuClass.registers["o" .. i] = { name = nil, count = 0 }
    end

    local memory = code or { "HLT" }
    cpuClass.memory = memory
    cpuClass.instruction_pointer = 1

    cpuClass.labels = module.parse_labels(memory)

    cpuClass.errors = {}

    -- Input signal tables, keyed by signal name, populated each tick by events.lua
    cpuClass.input_signals = {
        red   = {},
        green = {},
    }

    return cpuClass
end

function module:get_errors()
    return self.errors
end

function module:update_code(code)
    local memory = code or { "HLT" }
    self.memory = memory
    self.labels = module.parse_labels(memory)
    self.instruction_pointer = 1
    for i = 0, 31 do
        self.registers["x" .. i] = 0
    end
    for i = 0, 3 do
        self.registers["o" .. i] = { name = nil, count = 0 }
    end
    self.status = {
        is_halted = false,
        jump_executed = false,
        error = false,
    }
    self.errors = {}
    self.input_signals = {
        red   = {},
        green = {},
    }
end

function module:get_code()
    return self.memory
end

function module:step()
    if self.status.is_halted or self.status.error then
        return
    end

    local fetch = self.memory[self.instruction_pointer]
    if fetch == nil then
        self.status.error = true
        table.insert(self.errors, "No instruction at line " .. self.instruction_pointer)
        return
    end
    fetch = fetch:gsub("^[^:]*:%s*", "")           -- Remove label on current instruction
    fetch = fetch:gsub("#.*", ""):gsub("%s+$", "") -- Remove comments "#" and trailing whitespace

    local args = {}
    for arg in string.gmatch(fetch, "[^%s,]+") do
        table.insert(args, arg)
    end
    local instruction = table.remove(args, 1)
    -- Accept lower-case or mixed-case mnemonics; signal names and registers
    -- are left unchanged because they are case-sensitive in Factorio.
    if instruction ~= nil then
        instruction = instruction:upper()
    end

    if instruction == "HLT" then
        self.status.is_halted = true
        return
    elseif instruction == "NOP" then
        -- nop
    elseif instruction == "ADDI" then
        if #args ~= 3 then
            self.status.error = true
            table.insert(self.errors,
                "[ADDI:" ..
                self.instruction_pointer .. "] " .. "Unexpected number of arguments. ADDI expects 3, received " .. #args)
            return
        end
        if args[1] ~= "x0" then
            local rs = self.registers[args[2]]
            local imm = tonumber(args[3])
            if rs == nil or imm == nil then
                self.status.error = true
                table.insert(self.errors,
                    "[ADDI:" .. self.instruction_pointer .. "] Invalid register or immediate value")
                return
            end
            self.registers[args[1]] = rs + imm
        end
    elseif instruction == "LI" then
        -- Load immediate: LI rd, imm  =>  rd = imm
        -- Syntactic sugar for ADDI rd, x0, imm. Cleaner when loading a constant
        -- with no intent to add it to an existing register value.
        if #args ~= 2 then
            self.status.error = true
            table.insert(self.errors,
                "[LI:" .. self.instruction_pointer .. "] Expected 2 arguments (rd, imm), got " .. #args)
            return
        end
        if args[1] ~= "x0" then
            local imm = tonumber(args[2])
            if imm == nil then
                self.status.error = true
                table.insert(self.errors,
                    "[LI:" .. self.instruction_pointer .. "] Invalid immediate value: " .. args[2])
                return
            end
            if self.registers[args[1]] == nil then
                self.status.error = true
                table.insert(self.errors,
                    "[LI:" .. self.instruction_pointer .. "] Invalid destination register: " .. args[1])
                return
            end
            self.registers[args[1]] = imm
        end
    elseif instruction == "ADD" then
        if #args ~= 3 then
            self.status.error = true
            table.insert(self.errors,
                "[ADD:" ..
                self.instruction_pointer .. "] " .. "Unexpected number of arguments. Expected 3, got " .. #args)
            return
        end
        if args[1] ~= "x0" then
            local rs = self.registers[args[2]]
            local rt = self.registers[args[3]]
            if rs == nil or rt == nil then
                self.status.error = true
                table.insert(self.errors,
                    "[ADD:" .. self.instruction_pointer .. "] Invalid register name")
                return
            end
            self.registers[args[1]] = rs + rt
        end
    elseif instruction == "SUB" then
        if #args ~= 3 then
            self.status.error = true
            table.insert(self.errors,
                "[SUB:" ..
                self.instruction_pointer .. "] " .. "Unexpected number of arguments. Expected 3, got " .. #args)
            return
        end
        if args[1] ~= "x0" then
            local rs = self.registers[args[2]]
            local rt = self.registers[args[3]]
            if rs == nil or rt == nil then
                self.status.error = true
                table.insert(self.errors,
                    "[SUB:" .. self.instruction_pointer .. "] Invalid register name")
                return
            end
            self.registers[args[1]] = rs - rt
        end
    elseif instruction == "SLT" then
        if #args ~= 3 then
            self.status.error = true
            table.insert(self.errors,
                "[SLT:" ..
                self.instruction_pointer .. "] " .. "Unexpected number of arguments. Expected 3, got " .. #args)
            return
        end
        local rs = self.registers[args[2]]
        local rt = self.registers[args[3]]
        if rs == nil or rt == nil then
            self.status.error = true
            table.insert(self.errors,
                "[SLT:" .. self.instruction_pointer .. "] Invalid register name")
            return
        end
        if self.registers[args[1]] == nil and args[1] ~= "x0" then
            self.status.error = true
            table.insert(self.errors,
                "[SLT:" .. self.instruction_pointer .. "] Invalid destination register: " .. args[1])
            return
        end
        if rs < rt then
            self.registers[args[1]] = 1
        else
            self.registers[args[1]] = 0
        end
    elseif instruction == "SLTI" then
        if #args ~= 3 then
            self.status.error = true
            table.insert(self.errors,
                "[SLTI:" ..
                self.instruction_pointer .. "] " .. "Unexpected number of arguments. Expected 3, got " .. #args)
            return
        end
        local rs = self.registers[args[2]]
        local imm = tonumber(args[3])
        if rs == nil or imm == nil then
            self.status.error = true
            table.insert(self.errors,
                "[SLTI:" .. self.instruction_pointer .. "] Invalid register or immediate value")
            return
        end
        if rs < imm then
            self.registers[args[1]] = 1
        else
            self.registers[args[1]] = 0
        end
    elseif instruction == "WAIT" then
        if #args > 0 then
            if self.status["wait_cycles"] == nil then
                local register_pattern = "^x"
                if args[1]:find(register_pattern) ~= nil then
                    local val = self.registers[args[1]]
                    if val == nil then
                        self.status.error = true
                        table.insert(self.errors,
                            "[WAIT:" .. self.instruction_pointer .. "] Invalid register name: " .. args[1])
                        return
                    end
                    self.status["wait_cycles"] = val - 1
                else
                    local val = tonumber(args[1])
                    if val == nil then
                        self.status.error = true
                        table.insert(self.errors,
                            "[WAIT:" .. self.instruction_pointer .. "] Invalid wait value: " .. args[1])
                        return
                    end
                    self.status["wait_cycles"] = val - 1
                end
                return
            elseif self.status.wait_cycles > 1 then
                self.status.wait_cycles = self.status.wait_cycles - 1
                return
            else
                self.status.wait_cycles = nil
            end
        end
    elseif instruction == "WSIG" then
        if #args < 3 then
            self.status.error = true
            table.insert(self.errors,
                "[WSIG:" ..
                self.instruction_pointer .. "] " .. "Unexpected number of arguments. Expected 3, got " .. #args)
            return
        end
        local output_register_pattern = "^o"
        if args[1]:find(output_register_pattern) ~= nil then
            local count_reg = self.registers[args[3]]
            if count_reg == nil then
                self.status.error = true
                table.insert(self.errors,
                    "[WSIG:" .. self.instruction_pointer .. "] Invalid source register: " .. args[3])
                return
            end
            self.registers[args[1]] = { name = args[2], count = count_reg }
        else
            self.status.error = true
            table.insert(self.errors,
                "[WSIG:" ..
                self.instruction_pointer .. "] " .. "Unexpected output register name. Expected o0-o3, got " .. args[1])
            return
        end
    elseif instruction == "JAL" then
        if #args ~= 2 then
            self.status.error = true
            table.insert(self.errors,
                "[JAL:" ..
                self.instruction_pointer .. "] " .. "Unexpected number of arguments, expected 2, got " .. #args)
            return
        end
        local target = self.labels[args[2]]
        if target == nil then
            self.status.error = true
            table.insert(self.errors,
                "[JAL:" .. self.instruction_pointer .. "] Undefined label: " .. args[2])
            return
        end
        if args[1] ~= "x0" then
            -- Save IP+1: the line after this JAL, which is where JR should return to.
            -- This matches standard RISC-V convention (save PC+4, i.e. next instruction).
            if self.registers[args[1]] == nil then
                self.status.error = true
                table.insert(self.errors,
                    "[JAL:" .. self.instruction_pointer .. "] Invalid destination register: " .. args[1])
                return
            end
            self.registers[args[1]] = self.instruction_pointer + 1
        end
        self.instruction_pointer = target
        self.status.jump_executed = true
    elseif instruction == "BEQ" then
        if #args ~= 3 then
            self.status.error = true
            table.insert(self.errors,
                "[BEQ:" ..
                self.instruction_pointer .. "] " .. "Unexpected number of arguments, expected 3, got " .. #args)
            return
        end
        local rs = self.registers[args[1]]
        local rt = self.registers[args[2]]
        if rs == nil or rt == nil then
            self.status.error = true
            table.insert(self.errors,
                "[BEQ:" .. self.instruction_pointer .. "] Invalid register name")
            return
        end
        if rs == rt then
            local target = self.labels[args[3]]
            if target == nil then
                self.status.error = true
                table.insert(self.errors,
                    "[BEQ:" .. self.instruction_pointer .. "] Undefined label: " .. args[3])
                return
            end
            self.instruction_pointer = target
            self.status.jump_executed = true
        end
    elseif instruction == "BNE" then
        if #args ~= 3 then
            self.status.error = true
            table.insert(self.errors,
                "[BNE:" ..
                self.instruction_pointer .. "] " .. "Unexpected number of arguments, expected 3, got " .. #args)
            return
        end
        local rs = self.registers[args[1]]
        local rt = self.registers[args[2]]
        if rs == nil or rt == nil then
            self.status.error = true
            table.insert(self.errors,
                "[BNE:" .. self.instruction_pointer .. "] Invalid register name")
            return
        end
        if rs ~= rt then
            local target = self.labels[args[3]]
            if target == nil then
                self.status.error = true
                table.insert(self.errors,
                    "[BNE:" .. self.instruction_pointer .. "] Undefined label: " .. args[3])
                return
            end
            self.instruction_pointer = target
            self.status.jump_executed = true
        end
    elseif instruction == "RSIGR" then
        -- Read signal from Red network: RSIGR rd, signal-name
        -- Sets rd to the count of the named signal on the red input wire (0 if absent or unwired)
        if #args ~= 2 then
            self.status.error = true
            table.insert(self.errors,
                "[RSIGR:" ..
                self.instruction_pointer .. "] Unexpected number of arguments. Expected 2, got " .. #args)
            return
        end
        if args[1] ~= "x0" then
            if self.registers[args[1]] == nil then
                self.status.error = true
                table.insert(self.errors,
                    "[RSIGR:" .. self.instruction_pointer .. "] Invalid destination register: " .. args[1])
                return
            end
            self.registers[args[1]] = self.input_signals.red[args[2]] or 0
        end
    elseif instruction == "RSIGG" then
        -- Read signal from Green network: RSIGG rd, signal-name
        -- Sets rd to the count of the named signal on the green input wire (0 if absent or unwired)
        if #args ~= 2 then
            self.status.error = true
            table.insert(self.errors,
                "[RSIGG:" ..
                self.instruction_pointer .. "] Unexpected number of arguments. Expected 2, got " .. #args)
            return
        end
        if args[1] ~= "x0" then
            if self.registers[args[1]] == nil then
                self.status.error = true
                table.insert(self.errors,
                    "[RSIGG:" .. self.instruction_pointer .. "] Invalid destination register: " .. args[1])
                return
            end
            self.registers[args[1]] = self.input_signals.green[args[2]] or 0
        end
    elseif instruction == "MUL" then
        if #args ~= 3 then
            self.status.error = true
            table.insert(self.errors,
                "[MUL:" .. self.instruction_pointer .. "] Expected 3 arguments, got " .. #args)
            return
        end
        if args[1] ~= "x0" then
            local rs = self.registers[args[2]]
            local rt = self.registers[args[3]]
            if rs == nil or rt == nil then
                self.status.error = true
                table.insert(self.errors,
                    "[MUL:" .. self.instruction_pointer .. "] Invalid register name")
                return
            end
            self.registers[args[1]] = rs * rt
        end
    elseif instruction == "MULI" then
        if #args ~= 3 then
            self.status.error = true
            table.insert(self.errors,
                "[MULI:" .. self.instruction_pointer .. "] Expected 3 arguments, got " .. #args)
            return
        end
        if args[1] ~= "x0" then
            local rs  = self.registers[args[2]]
            local imm = tonumber(args[3])
            if rs == nil or imm == nil then
                self.status.error = true
                table.insert(self.errors,
                    "[MULI:" .. self.instruction_pointer .. "] Invalid register or immediate value")
                return
            end
            self.registers[args[1]] = rs * imm
        end
    elseif instruction == "DIV" then
        -- Integer division: DIV rd, rs, rt  =>  rd = floor(rs / rt)
        -- Matches Lua's integer division behaviour (truncates toward negative infinity).
        if #args ~= 3 then
            self.status.error = true
            table.insert(self.errors,
                "[DIV:" .. self.instruction_pointer .. "] Expected 3 arguments, got " .. #args)
            return
        end
        if args[1] ~= "x0" then
            local rs = self.registers[args[2]]
            local rt = self.registers[args[3]]
            if rs == nil or rt == nil then
                self.status.error = true
                table.insert(self.errors,
                    "[DIV:" .. self.instruction_pointer .. "] Invalid register name")
                return
            end
            if rt == 0 then
                self.status.error = true
                table.insert(self.errors,
                    "[DIV:" .. self.instruction_pointer .. "] Division by zero")
                return
            end
            self.registers[args[1]] = math.floor(rs / rt)
        end
    elseif instruction == "DIVI" then
        -- Integer division by immediate: DIVI rd, rs, imm  =>  rd = floor(rs / imm)
        if #args ~= 3 then
            self.status.error = true
            table.insert(self.errors,
                "[DIVI:" .. self.instruction_pointer .. "] Expected 3 arguments, got " .. #args)
            return
        end
        if args[1] ~= "x0" then
            local rs  = self.registers[args[2]]
            local imm = tonumber(args[3])
            if rs == nil or imm == nil then
                self.status.error = true
                table.insert(self.errors,
                    "[DIVI:" .. self.instruction_pointer .. "] Invalid register or immediate value")
                return
            end
            if imm == 0 then
                self.status.error = true
                table.insert(self.errors,
                    "[DIVI:" .. self.instruction_pointer .. "] Division by zero")
                return
            end
            self.registers[args[1]] = math.floor(rs / imm)
        end
    elseif instruction == "REM" then
        -- Remainder: REM rd, rs, rt  =>  rd = rs % rt
        -- Sign of result matches the dividend (rs), consistent with C's % operator
        -- and RISC-V's REM instruction. Uses Lua's math.fmod for this behaviour.
        if #args ~= 3 then
            self.status.error = true
            table.insert(self.errors,
                "[REM:" .. self.instruction_pointer .. "] Expected 3 arguments, got " .. #args)
            return
        end
        if args[1] ~= "x0" then
            local rs = self.registers[args[2]]
            local rt = self.registers[args[3]]
            if rs == nil or rt == nil then
                self.status.error = true
                table.insert(self.errors,
                    "[REM:" .. self.instruction_pointer .. "] Invalid register name")
                return
            end
            if rt == 0 then
                self.status.error = true
                table.insert(self.errors,
                    "[REM:" .. self.instruction_pointer .. "] Division by zero")
                return
            end
            self.registers[args[1]] = math.fmod(rs, rt)
        end
    elseif instruction == "REMI" then
        -- Remainder by immediate: REMI rd, rs, imm  =>  rd = rs % imm
        if #args ~= 3 then
            self.status.error = true
            table.insert(self.errors,
                "[REMI:" .. self.instruction_pointer .. "] Expected 3 arguments, got " .. #args)
            return
        end
        if args[1] ~= "x0" then
            local rs  = self.registers[args[2]]
            local imm = tonumber(args[3])
            if rs == nil or imm == nil then
                self.status.error = true
                table.insert(self.errors,
                    "[REMI:" .. self.instruction_pointer .. "] Invalid register or immediate value")
                return
            end
            if imm == 0 then
                self.status.error = true
                table.insert(self.errors,
                    "[REMI:" .. self.instruction_pointer .. "] Division by zero")
                return
            end
            self.registers[args[1]] = math.fmod(rs, imm)
        end
    elseif instruction == "AND" then
        if #args ~= 3 then
            self.status.error = true
            table.insert(self.errors,
                "[AND:" .. self.instruction_pointer .. "] Expected 3 arguments, got " .. #args)
            return
        end
        if args[1] ~= "x0" then
            local rs = self.registers[args[2]]
            local rt = self.registers[args[3]]
            if rs == nil or rt == nil then
                self.status.error = true
                table.insert(self.errors,
                    "[AND:" .. self.instruction_pointer .. "] Invalid register name")
                return
            end
            self.registers[args[1]] = _band(rs, rt)
        end
    elseif instruction == "OR" then
        if #args ~= 3 then
            self.status.error = true
            table.insert(self.errors,
                "[OR:" .. self.instruction_pointer .. "] Expected 3 arguments, got " .. #args)
            return
        end
        if args[1] ~= "x0" then
            local rs = self.registers[args[2]]
            local rt = self.registers[args[3]]
            if rs == nil or rt == nil then
                self.status.error = true
                table.insert(self.errors,
                    "[OR:" .. self.instruction_pointer .. "] Invalid register name")
                return
            end
            self.registers[args[1]] = _bor(rs, rt)
        end
    elseif instruction == "XOR" then
        if #args ~= 3 then
            self.status.error = true
            table.insert(self.errors,
                "[XOR:" .. self.instruction_pointer .. "] Expected 3 arguments, got " .. #args)
            return
        end
        if args[1] ~= "x0" then
            local rs = self.registers[args[2]]
            local rt = self.registers[args[3]]
            if rs == nil or rt == nil then
                self.status.error = true
                table.insert(self.errors,
                    "[XOR:" .. self.instruction_pointer .. "] Invalid register name")
                return
            end
            self.registers[args[1]] = _bxor(rs, rt)
        end
    elseif instruction == "NOT" then
        -- Unary bitwise NOT: NOT rd, rs  =>  rd = ~rs
        if #args ~= 2 then
            self.status.error = true
            table.insert(self.errors,
                "[NOT:" .. self.instruction_pointer .. "] Expected 2 arguments, got " .. #args)
            return
        end
        if args[1] ~= "x0" then
            local rs = self.registers[args[2]]
            if rs == nil then
                self.status.error = true
                table.insert(self.errors,
                    "[NOT:" .. self.instruction_pointer .. "] Invalid register name")
                return
            end
            self.registers[args[1]] = _bnot(rs)
        end
    elseif instruction == "SLL" then
        -- Shift left logical by register: SLL rd, rs, rt  =>  rd = rs << rt (zero-fill)
        if #args ~= 3 then
            self.status.error = true
            table.insert(self.errors,
                "[SLL:" .. self.instruction_pointer .. "] Expected 3 arguments, got " .. #args)
            return
        end
        if args[1] ~= "x0" then
            local rs = self.registers[args[2]]
            local rt = self.registers[args[3]]
            if rs == nil or rt == nil then
                self.status.error = true
                table.insert(self.errors,
                    "[SLL:" .. self.instruction_pointer .. "] Invalid register name")
                return
            end
            self.registers[args[1]] = _lshift(rs, rt)
        end
    elseif instruction == "SLLI" then
        -- Shift left logical by immediate: SLLI rd, rs, imm  =>  rd = rs << imm (zero-fill)
        if #args ~= 3 then
            self.status.error = true
            table.insert(self.errors,
                "[SLLI:" .. self.instruction_pointer .. "] Expected 3 arguments, got " .. #args)
            return
        end
        if args[1] ~= "x0" then
            local rs  = self.registers[args[2]]
            local imm = tonumber(args[3])
            if rs == nil or imm == nil then
                self.status.error = true
                table.insert(self.errors,
                    "[SLLI:" .. self.instruction_pointer .. "] Invalid register or immediate value")
                return
            end
            self.registers[args[1]] = _lshift(rs, imm)
        end
    elseif instruction == "SRA" then
        -- Shift right arithmetic by register: SRA rd, rs, rt  =>  rd = rs >> rt (sign-extend)
        if #args ~= 3 then
            self.status.error = true
            table.insert(self.errors,
                "[SRA:" .. self.instruction_pointer .. "] Expected 3 arguments, got " .. #args)
            return
        end
        if args[1] ~= "x0" then
            local rs = self.registers[args[2]]
            local rt = self.registers[args[3]]
            if rs == nil or rt == nil then
                self.status.error = true
                table.insert(self.errors,
                    "[SRA:" .. self.instruction_pointer .. "] Invalid register name")
                return
            end
            self.registers[args[1]] = _arshift(rs, rt)
        end
    elseif instruction == "SRAI" then
        -- Shift right arithmetic by immediate: SRAI rd, rs, imm  =>  rd = rs >> imm (sign-extend)
        if #args ~= 3 then
            self.status.error = true
            table.insert(self.errors,
                "[SRAI:" .. self.instruction_pointer .. "] Expected 3 arguments, got " .. #args)
            return
        end
        if args[1] ~= "x0" then
            local rs  = self.registers[args[2]]
            local imm = tonumber(args[3])
            if rs == nil or imm == nil then
                self.status.error = true
                table.insert(self.errors,
                    "[SRAI:" .. self.instruction_pointer .. "] Invalid register or immediate value")
                return
            end
            self.registers[args[1]] = _arshift(rs, imm)
        end
    elseif instruction == "SRL" then
        -- Shift right logical by register: SRL rd, rs, rt  =>  rd = rs >> rt (zero-fill)
        if #args ~= 3 then
            self.status.error = true
            table.insert(self.errors,
                "[SRL:" .. self.instruction_pointer .. "] Expected 3 arguments, got " .. #args)
            return
        end
        if args[1] ~= "x0" then
            local rs = self.registers[args[2]]
            local rt = self.registers[args[3]]
            if rs == nil or rt == nil then
                self.status.error = true
                table.insert(self.errors,
                    "[SRL:" .. self.instruction_pointer .. "] Invalid register name")
                return
            end
            self.registers[args[1]] = _rshift(rs, rt)
        end
    elseif instruction == "SRLI" then
        -- Shift right logical by immediate: SRLI rd, rs, imm  =>  rd = rs >> imm (zero-fill)
        if #args ~= 3 then
            self.status.error = true
            table.insert(self.errors,
                "[SRLI:" .. self.instruction_pointer .. "] Expected 3 arguments, got " .. #args)
            return
        end
        if args[1] ~= "x0" then
            local rs  = self.registers[args[2]]
            local imm = tonumber(args[3])
            if rs == nil or imm == nil then
                self.status.error = true
                table.insert(self.errors,
                    "[SRLI:" .. self.instruction_pointer .. "] Invalid register or immediate value")
                return
            end
            self.registers[args[1]] = _rshift(rs, imm)
        end
    elseif instruction == "CNTSR" then
        -- Count signals on Red input: CNTSR rd
        -- Sets rd to the number of distinct signals with non-zero count on the red wire
        if #args ~= 1 then
            self.status.error = true
            table.insert(self.errors,
                "[CNTSR:" .. self.instruction_pointer .. "] Expected 1 argument, got " .. #args)
            return
        end
        if args[1] ~= "x0" then
            if self.registers[args[1]] == nil then
                self.status.error = true
                table.insert(self.errors,
                    "[CNTSR:" .. self.instruction_pointer .. "] Invalid destination register: " .. args[1])
                return
            end
            local count = 0
            for _, _ in pairs(self.input_signals.red) do
                count = count + 1
            end
            self.registers[args[1]] = count
        end
    elseif instruction == "CNTSG" then
        -- Count signals on Green input: CNTSG rd
        -- Sets rd to the number of distinct signals with non-zero count on the green wire
        if #args ~= 1 then
            self.status.error = true
            table.insert(self.errors,
                "[CNTSG:" .. self.instruction_pointer .. "] Expected 1 argument, got " .. #args)
            return
        end
        if args[1] ~= "x0" then
            if self.registers[args[1]] == nil then
                self.status.error = true
                table.insert(self.errors,
                    "[CNTSG:" .. self.instruction_pointer .. "] Invalid destination register: " .. args[1])
                return
            end
            local count = 0
            for _, _ in pairs(self.input_signals.green) do
                count = count + 1
            end
            self.registers[args[1]] = count
        end
    elseif instruction == "BLT" then
        -- Branch if less than: BLT rs, rt, label — branch if rs < rt
        if #args ~= 3 then
            self.status.error = true
            table.insert(self.errors,
                "[BLT:" .. self.instruction_pointer .. "] Expected 3 arguments, got " .. #args)
            return
        end
        local rs = self.registers[args[1]]
        local rt = self.registers[args[2]]
        if rs == nil or rt == nil then
            self.status.error = true
            table.insert(self.errors,
                "[BLT:" .. self.instruction_pointer .. "] Invalid register name")
            return
        end
        if rs < rt then
            local target = self.labels[args[3]]
            if target == nil then
                self.status.error = true
                table.insert(self.errors,
                    "[BLT:" .. self.instruction_pointer .. "] Undefined label: " .. args[3])
                return
            end
            self.instruction_pointer = target
            self.status.jump_executed = true
        end
    elseif instruction == "BLE" then
        -- Branch if less than or equal: BLE rs, rt, label — branch if rs <= rt
        if #args ~= 3 then
            self.status.error = true
            table.insert(self.errors,
                "[BLE:" .. self.instruction_pointer .. "] Expected 3 arguments, got " .. #args)
            return
        end
        local rs = self.registers[args[1]]
        local rt = self.registers[args[2]]
        if rs == nil or rt == nil then
            self.status.error = true
            table.insert(self.errors,
                "[BLE:" .. self.instruction_pointer .. "] Invalid register name")
            return
        end
        if rs <= rt then
            local target = self.labels[args[3]]
            if target == nil then
                self.status.error = true
                table.insert(self.errors,
                    "[BLE:" .. self.instruction_pointer .. "] Undefined label: " .. args[3])
                return
            end
            self.instruction_pointer = target
            self.status.jump_executed = true
        end
    elseif instruction == "BGT" then
        -- Branch if greater than: BGT rs, rt, label — branch if rs > rt
        if #args ~= 3 then
            self.status.error = true
            table.insert(self.errors,
                "[BGT:" .. self.instruction_pointer .. "] Expected 3 arguments, got " .. #args)
            return
        end
        local rs = self.registers[args[1]]
        local rt = self.registers[args[2]]
        if rs == nil or rt == nil then
            self.status.error = true
            table.insert(self.errors,
                "[BGT:" .. self.instruction_pointer .. "] Invalid register name")
            return
        end
        if rs > rt then
            local target = self.labels[args[3]]
            if target == nil then
                self.status.error = true
                table.insert(self.errors,
                    "[BGT:" .. self.instruction_pointer .. "] Undefined label: " .. args[3])
                return
            end
            self.instruction_pointer = target
            self.status.jump_executed = true
        end
    elseif instruction == "BGE" then
        -- Branch if greater than or equal: BGE rs, rt, label — branch if rs >= rt
        if #args ~= 3 then
            self.status.error = true
            table.insert(self.errors,
                "[BGE:" .. self.instruction_pointer .. "] Expected 3 arguments, got " .. #args)
            return
        end
        local rs = self.registers[args[1]]
        local rt = self.registers[args[2]]
        if rs == nil or rt == nil then
            self.status.error = true
            table.insert(self.errors,
                "[BGE:" .. self.instruction_pointer .. "] Invalid register name")
            return
        end
        if rs >= rt then
            local target = self.labels[args[3]]
            if target == nil then
                self.status.error = true
                table.insert(self.errors,
                    "[BGE:" .. self.instruction_pointer .. "] Undefined label: " .. args[3])
                return
            end
            self.instruction_pointer = target
            self.status.jump_executed = true
        end
    elseif instruction == "JR" then
        -- Jump register: JR rs
        -- Jumps to the line stored in rs, which JAL now saves as IP+1 (the instruction
        -- after the call site). This is the standard subroutine return instruction.
        --
        -- Special case: JR x0 always jumps to line 1 (top of program), since x0 is
        -- hardwired to 0 and 0 is not a valid line number. This provides a convenient
        -- unconditional restart without requiring a label on line 1.
        if #args ~= 1 then
            self.status.error = true
            table.insert(self.errors,
                "[JR:" .. self.instruction_pointer .. "] Expected 1 argument (register), got " .. #args)
            return
        end
        local rs = self.registers[args[1]]
        if rs == nil then
            self.status.error = true
            table.insert(self.errors,
                "[JR:" .. self.instruction_pointer .. "] Invalid register name: " .. args[1])
            return
        end
        -- x0 is always 0; treat JR x0 as "jump to line 1" (restart)
        local target = (rs == 0) and 1 or rs
        if target < 1 or target > #self.memory then
            self.status.error = true
            table.insert(self.errors,
                "[JR:" .. self.instruction_pointer .. "] Return address out of range: " .. target)
            return
        end
        self.instruction_pointer = target
        self.status.jump_executed = true
        elseif instruction == "BEQI" then
        -- BEQI rs, imm, label — branch if rs == imm
        if #args ~= 3 then
            self.status.error = true
            table.insert(self.errors,
                "[BEQI:" .. self.instruction_pointer .. "] Expected 3 arguments, got " .. #args)
            return
        end
        local rs  = self.registers[args[1]]
        local imm = tonumber(args[2])
        if rs == nil then
            self.status.error = true
            table.insert(self.errors,
                "[BEQI:" .. self.instruction_pointer .. "] Invalid register name: " .. args[1])
            return
        end
        if imm == nil then
            self.status.error = true
            table.insert(self.errors,
                "[BEQI:" .. self.instruction_pointer .. "] Invalid immediate value: " .. args[2])
            return
        end
        if rs == imm then
            local target = self.labels[args[3]]
            if target == nil then
                self.status.error = true
                table.insert(self.errors,
                    "[BEQI:" .. self.instruction_pointer .. "] Undefined label: " .. args[3])
                return
            end
            self.instruction_pointer = target
            self.status.jump_executed = true
        end
    elseif instruction == "BNEI" then
        -- BNEI rs, imm, label — branch if rs ~= imm
        if #args ~= 3 then
            self.status.error = true
            table.insert(self.errors,
                "[BNEI:" .. self.instruction_pointer .. "] Expected 3 arguments, got " .. #args)
            return
        end
        local rs  = self.registers[args[1]]
        local imm = tonumber(args[2])
        if rs == nil then
            self.status.error = true
            table.insert(self.errors,
                "[BNEI:" .. self.instruction_pointer .. "] Invalid register name: " .. args[1])
            return
        end
        if imm == nil then
            self.status.error = true
            table.insert(self.errors,
                "[BNEI:" .. self.instruction_pointer .. "] Invalid immediate value: " .. args[2])
            return
        end
        if rs ~= imm then
            local target = self.labels[args[3]]
            if target == nil then
                self.status.error = true
                table.insert(self.errors,
                    "[BNEI:" .. self.instruction_pointer .. "] Undefined label: " .. args[3])
                return
            end
            self.instruction_pointer = target
            self.status.jump_executed = true
        end
    elseif instruction == "BLTI" then
        -- BLTI rs, imm, label — branch if rs < imm
        if #args ~= 3 then
            self.status.error = true
            table.insert(self.errors,
                "[BLTI:" .. self.instruction_pointer .. "] Expected 3 arguments, got " .. #args)
            return
        end
        local rs  = self.registers[args[1]]
        local imm = tonumber(args[2])
        if rs == nil then
            self.status.error = true
            table.insert(self.errors,
                "[BLTI:" .. self.instruction_pointer .. "] Invalid register name: " .. args[1])
            return
        end
        if imm == nil then
            self.status.error = true
            table.insert(self.errors,
                "[BLTI:" .. self.instruction_pointer .. "] Invalid immediate value: " .. args[2])
            return
        end
        if rs < imm then
            local target = self.labels[args[3]]
            if target == nil then
                self.status.error = true
                table.insert(self.errors,
                    "[BLTI:" .. self.instruction_pointer .. "] Undefined label: " .. args[3])
                return
            end
            self.instruction_pointer = target
            self.status.jump_executed = true
        end
    elseif instruction == "BLEI" then
        -- BLEI rs, imm, label — branch if rs <= imm
        if #args ~= 3 then
            self.status.error = true
            table.insert(self.errors,
                "[BLEI:" .. self.instruction_pointer .. "] Expected 3 arguments, got " .. #args)
            return
        end
        local rs  = self.registers[args[1]]
        local imm = tonumber(args[2])
        if rs == nil then
            self.status.error = true
            table.insert(self.errors,
                "[BLEI:" .. self.instruction_pointer .. "] Invalid register name: " .. args[1])
            return
        end
        if imm == nil then
            self.status.error = true
            table.insert(self.errors,
                "[BLEI:" .. self.instruction_pointer .. "] Invalid immediate value: " .. args[2])
            return
        end
        if rs <= imm then
            local target = self.labels[args[3]]
            if target == nil then
                self.status.error = true
                table.insert(self.errors,
                    "[BLEI:" .. self.instruction_pointer .. "] Undefined label: " .. args[3])
                return
            end
            self.instruction_pointer = target
            self.status.jump_executed = true
        end
    elseif instruction == "BGTI" then
        -- BGTI rs, imm, label — branch if rs > imm
        if #args ~= 3 then
            self.status.error = true
            table.insert(self.errors,
                "[BGTI:" .. self.instruction_pointer .. "] Expected 3 arguments, got " .. #args)
            return
        end
        local rs  = self.registers[args[1]]
        local imm = tonumber(args[2])
        if rs == nil then
            self.status.error = true
            table.insert(self.errors,
                "[BGTI:" .. self.instruction_pointer .. "] Invalid register name: " .. args[1])
            return
        end
        if imm == nil then
            self.status.error = true
            table.insert(self.errors,
                "[BGTI:" .. self.instruction_pointer .. "] Invalid immediate value: " .. args[2])
            return
        end
        if rs > imm then
            local target = self.labels[args[3]]
            if target == nil then
                self.status.error = true
                table.insert(self.errors,
                    "[BGTI:" .. self.instruction_pointer .. "] Undefined label: " .. args[3])
                return
            end
            self.instruction_pointer = target
            self.status.jump_executed = true
        end
    elseif instruction == "BGEI" then
        -- BGEI rs, imm, label — branch if rs >= imm
        if #args ~= 3 then
            self.status.error = true
            table.insert(self.errors,
                "[BGEI:" .. self.instruction_pointer .. "] Expected 3 arguments, got " .. #args)
            return
        end
        local rs  = self.registers[args[1]]
        local imm = tonumber(args[2])
        if rs == nil then
            self.status.error = true
            table.insert(self.errors,
                "[BGEI:" .. self.instruction_pointer .. "] Invalid register name: " .. args[1])
            return
        end
        if imm == nil then
            self.status.error = true
            table.insert(self.errors,
                "[BGEI:" .. self.instruction_pointer .. "] Invalid immediate value: " .. args[2])
            return
        end
        if rs >= imm then
            local target = self.labels[args[3]]
            if target == nil then
                self.status.error = true
                table.insert(self.errors,
                    "[BGEI:" .. self.instruction_pointer .. "] Undefined label: " .. args[3])
                return
            end
            self.instruction_pointer = target
            self.status.jump_executed = true
        end
        else
        if instruction ~= nil then
            table.insert(self.errors, "Unexpected instruction on line " .. self.instruction_pointer .. ": " ..
                instruction)
            self.status.error = true
            return
        end
    end

    self:advance_ip()
end

function module:advance_ip()
    if self.status.is_halted or self.status.error then
        return
    end
    if self.status.jump_executed then
        self.status.jump_executed = false
        return
    end
    self.instruction_pointer = (self.instruction_pointer % #self.memory) + 1
end

function module:is_halted()
    return self.status.is_halted
end

function module:get_register(register_name)
    return self.registers[register_name]
end

-- Called each tick by events.lua with tables of { [signal_name] = count }
function module:set_input_signals(red_signals, green_signals)
    self.input_signals.red   = red_signals   or {}
    self.input_signals.green = green_signals or {}
end

return module
