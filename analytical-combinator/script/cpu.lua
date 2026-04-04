local module = {}
module.__index = module

-- LuaJIT (Factorio's runtime) implements Lua 5.1 — the bitwise operators
-- &, |, ~, <<, >> do not exist. Use the bit library instead.
-- LuaJIT ships "bit" built-in; standard Lua 5.2 has "bit32". Try both.
local _bitlib  = bit32 or bit
local _band    = _bitlib.band
local _bor     = _bitlib.bor
local _bxor    = _bitlib.bxor
local _bnot    = _bitlib.bnot
local _lshift  = _bitlib.lshift
local _rshift  = _bitlib.rshift    -- logical (zero-fill)
local _arshift = _bitlib.arshift   -- arithmetic (sign-extend)

-- ── Prototype lookup helpers ──────────────────────────────────────────────────

local function valid_signal_name(name)
    return prototypes.virtual_signal[name] ~= nil
        or prototypes.item[name]           ~= nil
        or prototypes.fluid[name]          ~= nil
end

-- ── Register classification helpers ──────────────────────────────────────────

local function is_gp_reg(name)
    -- General-purpose register: x0–x31
    if type(name) ~= "string" then return false end
    local n = name:match("^x(%d+)$")
    if not n then return false end
    n = tonumber(n)
    return n ~= nil and n >= 0 and n <= 31
end

local function is_out_reg(name)
    -- Output register: o0–o3
    if type(name) ~= "string" then return false end
    local n = name:match("^o(%d+)$")
    if not n then return false end
    n = tonumber(n)
    return n ~= nil and n >= 0 and n <= 3
end

-- ── Label parsing ─────────────────────────────────────────────────────────────

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

-- ── Token extraction (shared by validator and step()) ────────────────────────

local function tokenize(line)
    local stripped = line:gsub("^[^:]*:%s*", "")
                         :gsub("#.*", "")
                         :gsub("%s+$", "")
    local tokens = {}
    for tok in string.gmatch(stripped, "[^%s,]+") do
        table.insert(tokens, tok)
    end
    return tokens
end

-- ── Load-time validator ───────────────────────────────────────────────────────
--
-- Checks every instruction once when code is loaded or saved. step() runs
-- with no validation, trusting all registers, immediates, signal names, and
-- labels were already verified here.
--
-- Argument descriptor types:
--   "rd"          destination general-purpose register (x0-x31)
--   "rs" / "rt"   source general-purpose register     (x0-x31)
--   "od"          output register                     (o0-o3)
--   "imm"         integer immediate (decimal or 0x hex)
--   "sig"         signal name validated against Factorio prototypes
--   "lbl"         label name that must exist in the program
--   "reg_or_imm"  either a gp register or an integer immediate (WAIT)

local INSTR = {
    HLT  = { 0, {} },
    NOP  = { 0, {} },
    LI   = { 2, { "rd",  "imm"       } },
    ADDI = { 3, { "rd",  "rs",  "imm" } },
    ADD  = { 3, { "rd",  "rs",  "rt"  } },
    SUB  = { 3, { "rd",  "rs",  "rt"  } },
    MUL  = { 3, { "rd",  "rs",  "rt"  } },
    MULI = { 3, { "rd",  "rs",  "imm" } },
    DIV  = { 3, { "rd",  "rs",  "rt"  } },
    DIVI = { 3, { "rd",  "rs",  "imm" } },
    REM  = { 3, { "rd",  "rs",  "rt"  } },
    REMI = { 3, { "rd",  "rs",  "imm" } },
    SLT  = { 3, { "rd",  "rs",  "rt"  } },
    SLTI = { 3, { "rd",  "rs",  "imm" } },
    AND  = { 3, { "rd",  "rs",  "rt"  } },
    OR   = { 3, { "rd",  "rs",  "rt"  } },
    XOR  = { 3, { "rd",  "rs",  "rt"  } },
    NOT  = { 2, { "rd",  "rs"         } },
    SLL  = { 3, { "rd",  "rs",  "rt"  } },
    SLLI = { 3, { "rd",  "rs",  "imm" } },
    SRL  = { 3, { "rd",  "rs",  "rt"  } },
    SRLI = { 3, { "rd",  "rs",  "imm" } },
    SRA  = { 3, { "rd",  "rs",  "rt"  } },
    SRAI = { 3, { "rd",  "rs",  "imm" } },
    JAL  = { 2, { "rd",  "lbl"        } },
    JR   = { 1, { "rs"               } },
    BEQ  = { 3, { "rs",  "rt",  "lbl" } },
    BNE  = { 3, { "rs",  "rt",  "lbl" } },
    BLT  = { 3, { "rs",  "rt",  "lbl" } },
    BLE  = { 3, { "rs",  "rt",  "lbl" } },
    BGT  = { 3, { "rs",  "rt",  "lbl" } },
    BGE  = { 3, { "rs",  "rt",  "lbl" } },
    BEQI = { 3, { "rs",  "imm", "lbl" } },
    BNEI = { 3, { "rs",  "imm", "lbl" } },
    BLTI = { 3, { "rs",  "imm", "lbl" } },
    BLEI = { 3, { "rs",  "imm", "lbl" } },
    BGTI = { 3, { "rs",  "imm", "lbl" } },
    BGEI = { 3, { "rs",  "imm", "lbl" } },
    RSIG  = { 2, { "rd",  "sig"        } },
    RSIGR = { 2, { "rd",  "sig"        } },
    RSIGG = { 2, { "rd",  "sig"        } },
    WSIG  = { 3, { "od",  "sig", "rs"  } },
    WSIGI = { 3, { "od",  "sig", "imm" } },
    CNTSR = { 1, { "rd"               } },
    CNTSG = { 1, { "rd"               } },
    WAIT  = { 1, { "reg_or_imm"       } },
}

function module.validate_program(memory)
    local labels = module.parse_labels(memory)
    local errors = {}

    local function err(line_num, mnemonic, msg)
        table.insert(errors, "[" .. mnemonic .. ":" .. line_num .. "] " .. msg)
    end

    for line_num, line in ipairs(memory) do
        local tokens = tokenize(line)
        if #tokens == 0 then goto continue end

        local mnemonic = tokens[1]:upper()
        local desc = INSTR[mnemonic]

        if desc == nil then
            err(line_num, mnemonic, "Unknown instruction: " .. tokens[1])
            goto continue
        end

        local expected_nargs = desc[1]
        local actual_nargs   = #tokens - 1

        if actual_nargs ~= expected_nargs then
            err(line_num, mnemonic,
                "Expected " .. expected_nargs .. " argument(s), got " .. actual_nargs)
            goto continue
        end

        for i, arg_type in ipairs(desc[2]) do
            local val = tokens[i + 1]
            if arg_type == "rd" or arg_type == "rs" or arg_type == "rt" then
                if not is_gp_reg(val) then
                    err(line_num, mnemonic,
                        "Argument " .. i .. ": expected register x0-x31, got '" .. val .. "'")
                end
            elseif arg_type == "od" then
                if not is_out_reg(val) then
                    err(line_num, mnemonic,
                        "Argument " .. i .. ": expected output register o0-o3, got '" .. val .. "'")
                end
            elseif arg_type == "imm" then
                if tonumber(val) == nil then
                    err(line_num, mnemonic,
                        "Argument " .. i .. ": expected integer immediate, got '" .. val .. "'")
                end
            elseif arg_type == "sig" then
                if not valid_signal_name(val) then
                    err(line_num, mnemonic,
                        "Argument " .. i .. ": unknown signal name '" .. val .. "'")
                end
            elseif arg_type == "lbl" then
                if labels[val] == nil then
                    err(line_num, mnemonic,
                        "Argument " .. i .. ": undefined label '" .. val .. "'")
                end
            elseif arg_type == "reg_or_imm" then
                if not is_gp_reg(val) and tonumber(val) == nil then
                    err(line_num, mnemonic,
                        "Argument " .. i .. ": expected register x0-x31 or integer, got '" .. val .. "'")
                end
            end
        end

        ::continue::
    end

    return errors
end

-- ── CPU lifecycle ─────────────────────────────────────────────────────────────

local function apply_validation(cpu_state, memory)
    local errs = module.validate_program(memory)
    for _, e in ipairs(errs) do
        table.insert(cpu_state.errors, e)
    end
    if #errs > 0 then
        cpu_state.status.error = true
    end
end

function module.new(code)
    local cpuClass = setmetatable({}, module)
    cpuClass.status = { is_halted = false, jump_executed = false, error = false }
    cpuClass.registers = {}
    for i = 0, 31 do cpuClass.registers["x" .. i] = 0 end
    for i = 0, 3  do cpuClass.registers["o" .. i] = { name = nil, count = 0 } end
    local memory = code or { "HLT" }
    cpuClass.memory             = memory
    cpuClass.instruction_pointer = 1
    cpuClass.labels             = module.parse_labels(memory)
    cpuClass.errors             = {}
    cpuClass.input_signals      = { red = {}, green = {} }
    apply_validation(cpuClass, memory)
    return cpuClass
end

function module:get_errors()
    return self.errors
end

function module:update_code(code)
    local memory = code or { "HLT" }
    self.memory             = memory
    self.labels             = module.parse_labels(memory)
    self.instruction_pointer = 1
    for i = 0, 31 do self.registers["x" .. i] = 0 end
    for i = 0, 3  do self.registers["o" .. i] = { name = nil, count = 0 } end
    self.status        = { is_halted = false, jump_executed = false, error = false }
    self.errors        = {}
    self.input_signals = { red = {}, green = {} }
    apply_validation(self, memory)
end

function module:get_code()
    return self.memory
end

-- ── Instruction execution ─────────────────────────────────────────────────────
-- validate_program() already confirmed every register, immediate, signal name,
-- and label. No validation here — pure computation only.
-- Exception: divide-by-zero (divisor only known at runtime).

function module:step()
    if self.status.is_halted or self.status.error then return end

    local fetch = self.memory[self.instruction_pointer]
    if fetch == nil then
        self.status.error = true
        table.insert(self.errors, "No instruction at line " .. self.instruction_pointer)
        return
    end

    local tokens = tokenize(fetch)
    if #tokens == 0 then self:advance_ip(); return end

    local instruction = tokens[1]:upper()
    local args = {}
    for i = 2, #tokens do args[i-1] = tokens[i] end

    if instruction == "HLT" then
        self.status.is_halted = true; return

    elseif instruction == "NOP" then  -- nothing

    elseif instruction == "LI" then
        if args[1] ~= "x0" then
            self.registers[args[1]] = tonumber(args[2])
        end

    elseif instruction == "ADDI" then
        if args[1] ~= "x0" then
            self.registers[args[1]] = self.registers[args[2]] + tonumber(args[3])
        end

    elseif instruction == "ADD" then
        if args[1] ~= "x0" then
            self.registers[args[1]] = self.registers[args[2]] + self.registers[args[3]]
        end

    elseif instruction == "SUB" then
        if args[1] ~= "x0" then
            self.registers[args[1]] = self.registers[args[2]] - self.registers[args[3]]
        end

    elseif instruction == "MUL" then
        if args[1] ~= "x0" then
            self.registers[args[1]] = self.registers[args[2]] * self.registers[args[3]]
        end

    elseif instruction == "MULI" then
        if args[1] ~= "x0" then
            self.registers[args[1]] = self.registers[args[2]] * tonumber(args[3])
        end

    elseif instruction == "DIV" then
        if args[1] ~= "x0" then
            local rt = self.registers[args[3]]
            if rt == 0 then
                self.status.error = true
                table.insert(self.errors, "[DIV:" .. self.instruction_pointer .. "] Division by zero")
                return
            end
            self.registers[args[1]] = math.floor(self.registers[args[2]] / rt)
        end

    elseif instruction == "DIVI" then
        if args[1] ~= "x0" then
            local imm = tonumber(args[3])
            if imm == 0 then
                self.status.error = true
                table.insert(self.errors, "[DIVI:" .. self.instruction_pointer .. "] Division by zero")
                return
            end
            self.registers[args[1]] = math.floor(self.registers[args[2]] / imm)
        end

    elseif instruction == "REM" then
        if args[1] ~= "x0" then
            local rt = self.registers[args[3]]
            if rt == 0 then
                self.status.error = true
                table.insert(self.errors, "[REM:" .. self.instruction_pointer .. "] Division by zero")
                return
            end
            self.registers[args[1]] = math.fmod(self.registers[args[2]], rt)
        end

    elseif instruction == "REMI" then
        if args[1] ~= "x0" then
            local imm = tonumber(args[3])
            if imm == 0 then
                self.status.error = true
                table.insert(self.errors, "[REMI:" .. self.instruction_pointer .. "] Division by zero")
                return
            end
            self.registers[args[1]] = math.fmod(self.registers[args[2]], imm)
        end

    elseif instruction == "SLT" then
        if args[1] ~= "x0" then
            self.registers[args[1]] = (self.registers[args[2]] < self.registers[args[3]]) and 1 or 0
        end

    elseif instruction == "SLTI" then
        if args[1] ~= "x0" then
            self.registers[args[1]] = (self.registers[args[2]] < tonumber(args[3])) and 1 or 0
        end

    elseif instruction == "AND" then
        if args[1] ~= "x0" then
            self.registers[args[1]] = _band(self.registers[args[2]], self.registers[args[3]])
        end

    elseif instruction == "OR" then
        if args[1] ~= "x0" then
            self.registers[args[1]] = _bor(self.registers[args[2]], self.registers[args[3]])
        end

    elseif instruction == "XOR" then
        if args[1] ~= "x0" then
            self.registers[args[1]] = _bxor(self.registers[args[2]], self.registers[args[3]])
        end

    elseif instruction == "NOT" then
        if args[1] ~= "x0" then
            self.registers[args[1]] = _bnot(self.registers[args[2]])
        end

    elseif instruction == "SLL" then
        if args[1] ~= "x0" then
            self.registers[args[1]] = _lshift(self.registers[args[2]], self.registers[args[3]])
        end

    elseif instruction == "SLLI" then
        if args[1] ~= "x0" then
            self.registers[args[1]] = _lshift(self.registers[args[2]], tonumber(args[3]))
        end

    elseif instruction == "SRL" then
        if args[1] ~= "x0" then
            self.registers[args[1]] = _rshift(self.registers[args[2]], self.registers[args[3]])
        end

    elseif instruction == "SRLI" then
        if args[1] ~= "x0" then
            self.registers[args[1]] = _rshift(self.registers[args[2]], tonumber(args[3]))
        end

    elseif instruction == "SRA" then
        if args[1] ~= "x0" then
            self.registers[args[1]] = _arshift(self.registers[args[2]], self.registers[args[3]])
        end

    elseif instruction == "SRAI" then
        if args[1] ~= "x0" then
            self.registers[args[1]] = _arshift(self.registers[args[2]], tonumber(args[3]))
        end

    elseif instruction == "WAIT" then
        if #args > 0 then
            if self.status.wait_cycles == nil then
                local val = self.registers[args[1]]
                if val == nil then val = tonumber(args[1]) end
                self.status.wait_cycles = val - 1
                return
            elseif self.status.wait_cycles > 1 then
                self.status.wait_cycles = self.status.wait_cycles - 1
                return
            else
                self.status.wait_cycles = nil
            end
        end

    elseif instruction == "WSIG" then
        self.registers[args[1]] = { name = args[2], count = self.registers[args[3]] }

    elseif instruction == "WSIGI" then
        -- Write signal immediate: WSIGI od, signal, imm
        -- Outputs the signal with a constant count, no register needed.
        self.registers[args[1]] = { name = args[2], count = tonumber(args[3]) }

    elseif instruction == "JAL" then
        if args[1] ~= "x0" then
            self.registers[args[1]] = self.instruction_pointer + 1
        end
        self.instruction_pointer = self.labels[args[2]]
        self.status.jump_executed = true

    elseif instruction == "JR" then
        local rs = self.registers[args[1]]
        local target = (rs == 0) and 1 or rs
        if target < 1 or target > #self.memory then
            self.status.error = true
            table.insert(self.errors,
                "[JR:" .. self.instruction_pointer .. "] Return address out of range: " .. target)
            return
        end
        self.instruction_pointer = target
        self.status.jump_executed = true

    elseif instruction == "BEQ" then
        if self.registers[args[1]] == self.registers[args[2]] then
            self.instruction_pointer = self.labels[args[3]]
            self.status.jump_executed = true
        end

    elseif instruction == "BNE" then
        if self.registers[args[1]] ~= self.registers[args[2]] then
            self.instruction_pointer = self.labels[args[3]]
            self.status.jump_executed = true
        end

    elseif instruction == "BLT" then
        if self.registers[args[1]] < self.registers[args[2]] then
            self.instruction_pointer = self.labels[args[3]]
            self.status.jump_executed = true
        end

    elseif instruction == "BLE" then
        if self.registers[args[1]] <= self.registers[args[2]] then
            self.instruction_pointer = self.labels[args[3]]
            self.status.jump_executed = true
        end

    elseif instruction == "BGT" then
        if self.registers[args[1]] > self.registers[args[2]] then
            self.instruction_pointer = self.labels[args[3]]
            self.status.jump_executed = true
        end

    elseif instruction == "BGE" then
        if self.registers[args[1]] >= self.registers[args[2]] then
            self.instruction_pointer = self.labels[args[3]]
            self.status.jump_executed = true
        end

    elseif instruction == "BEQI" then
        if self.registers[args[1]] == tonumber(args[2]) then
            self.instruction_pointer = self.labels[args[3]]
            self.status.jump_executed = true
        end

    elseif instruction == "BNEI" then
        if self.registers[args[1]] ~= tonumber(args[2]) then
            self.instruction_pointer = self.labels[args[3]]
            self.status.jump_executed = true
        end

    elseif instruction == "BLTI" then
        if self.registers[args[1]] < tonumber(args[2]) then
            self.instruction_pointer = self.labels[args[3]]
            self.status.jump_executed = true
        end

    elseif instruction == "BLEI" then
        if self.registers[args[1]] <= tonumber(args[2]) then
            self.instruction_pointer = self.labels[args[3]]
            self.status.jump_executed = true
        end

    elseif instruction == "BGTI" then
        if self.registers[args[1]] > tonumber(args[2]) then
            self.instruction_pointer = self.labels[args[3]]
            self.status.jump_executed = true
        end

    elseif instruction == "BGEI" then
        if self.registers[args[1]] >= tonumber(args[2]) then
            self.instruction_pointer = self.labels[args[3]]
            self.status.jump_executed = true
        end

    elseif instruction == "RSIG" then
        if args[1] ~= "x0" then
            self.registers[args[1]] = (self.input_signals.red[args[2]]   or 0)
                                    + (self.input_signals.green[args[2]] or 0)
        end

    elseif instruction == "RSIGR" then
        if args[1] ~= "x0" then
            self.registers[args[1]] = self.input_signals.red[args[2]] or 0
        end

    elseif instruction == "RSIGG" then
        if args[1] ~= "x0" then
            self.registers[args[1]] = self.input_signals.green[args[2]] or 0
        end

    elseif instruction == "CNTSR" then
        if args[1] ~= "x0" then
            local count = 0
            for _ in pairs(self.input_signals.red) do count = count + 1 end
            self.registers[args[1]] = count
        end

    elseif instruction == "CNTSG" then
        if args[1] ~= "x0" then
            local count = 0
            for _ in pairs(self.input_signals.green) do count = count + 1 end
            self.registers[args[1]] = count
        end

    else
        if instruction ~= nil then
            self.status.error = true
            table.insert(self.errors,
                "Unexpected instruction on line " .. self.instruction_pointer .. ": " .. instruction)
        end
        return
    end

    self:advance_ip()
end

function module:advance_ip()
    if self.status.is_halted or self.status.error then return end
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
