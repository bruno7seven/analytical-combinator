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
    if type(name) ~= "string" then return false end
    local n = tonumber(name:match("^x(%d+)$"))
    return n ~= nil and n >= 0 and n <= 31
end

local function is_out_reg(name)
    if type(name) ~= "string" then return false end
    local n = tonumber(name:match("^o(%d+)$"))
    return n ~= nil and n >= 0 and n <= 3
end

-- ── Label parsing ─────────────────────────────────────────────────────────────

function module.parse_labels(code)
    local labels = {}
    for i, line in ipairs(code) do
        local label = line:match("^%s*([%w_][%w_]*):%s*")
        if label then labels[label] = i end
    end
    return labels
end

function module.extract_label_name(line)
    return line:match("^%s*([%w_][%w_]*):.*$")
end

-- ── Tokenizer ─────────────────────────────────────────────────────────────────

local function tokenize(line)
    local stripped = line:gsub("^[^:]*:%s*", "")
                         :gsub("#.*", "")
                         :gsub("%s+$", "")
    local tokens = {}
    for tok in stripped:gmatch("[^%s,]+") do
        table.insert(tokens, tok)
    end
    return tokens
end

-- ── Load-time validator ───────────────────────────────────────────────────────
--
-- Validates every instruction once at load time. step() runs with no validation.
-- The only runtime check is divide-by-zero (divisor only known at runtime).
--
-- Argument descriptor types:
--   "rd" / "rs" / "rt"  general-purpose register (x0-x31)
--   "od"                 output register (o0-o3)
--   "imm"                integer immediate (decimal or 0x hex)
--   "sig"                signal name validated against Factorio prototypes
--   "lbl"                label that must exist in the program
--   "reg_or_imm"         either a gp register or an integer (WAIT)

local INSTR = {
    HLT   = { 0, {} },
    NOP   = { 0, {} },
    LI    = { 2, { "rd",  "imm"       } },
    ADDI  = { 3, { "rd",  "rs",  "imm" } },
    ADD   = { 3, { "rd",  "rs",  "rt"  } },
    SUB   = { 3, { "rd",  "rs",  "rt"  } },
    MUL   = { 3, { "rd",  "rs",  "rt"  } },
    MULI  = { 3, { "rd",  "rs",  "imm" } },
    DIV   = { 3, { "rd",  "rs",  "rt"  } },
    DIVI  = { 3, { "rd",  "rs",  "imm" } },
    REM   = { 3, { "rd",  "rs",  "rt"  } },
    REMI  = { 3, { "rd",  "rs",  "imm" } },
    SLT   = { 3, { "rd",  "rs",  "rt"  } },
    SLTI  = { 3, { "rd",  "rs",  "imm" } },
    AND   = { 3, { "rd",  "rs",  "rt"  } },
    OR    = { 3, { "rd",  "rs",  "rt"  } },
    XOR   = { 3, { "rd",  "rs",  "rt"  } },
    NOT   = { 2, { "rd",  "rs"         } },
    SLL   = { 3, { "rd",  "rs",  "rt"  } },
    SLLI  = { 3, { "rd",  "rs",  "imm" } },
    SRL   = { 3, { "rd",  "rs",  "rt"  } },
    SRLI  = { 3, { "rd",  "rs",  "imm" } },
    SRA   = { 3, { "rd",  "rs",  "rt"  } },
    SRAI  = { 3, { "rd",  "rs",  "imm" } },
    JAL   = { 2, { "rd",  "lbl"        } },
    JR    = { 1, { "rs"               } },
    BEQ   = { 3, { "rs",  "rt",  "lbl" } },
    BNE   = { 3, { "rs",  "rt",  "lbl" } },
    BLT   = { 3, { "rs",  "rt",  "lbl" } },
    BLE   = { 3, { "rs",  "rt",  "lbl" } },
    BGT   = { 3, { "rs",  "rt",  "lbl" } },
    BGE   = { 3, { "rs",  "rt",  "lbl" } },
    BEQI  = { 3, { "rs",  "imm", "lbl" } },
    BNEI  = { 3, { "rs",  "imm", "lbl" } },
    BLTI  = { 3, { "rs",  "imm", "lbl" } },
    BLEI  = { 3, { "rs",  "imm", "lbl" } },
    BGTI  = { 3, { "rs",  "imm", "lbl" } },
    BGEI  = { 3, { "rs",  "imm", "lbl" } },
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

-- ── Pre-compilation ───────────────────────────────────────────────────────────
--
-- Converts the raw source line array into a "compiled" array of instruction
-- records that step() can execute with no string operations at all.
--
-- Each compiled record is a table:
--   { op = "ADDI", a1 = "x10", a2 = "x0", a3 = 255 }
--
-- Key optimisation: immediate arguments are resolved to numbers here, so
-- tonumber() is never called inside step(). Label arguments are resolved to
-- line numbers. WAIT's argument is resolved to either a register name string
-- or a pre-converted integer. Empty/label-only lines become { op = "NOP" }.
--
-- This function is only called after validate_program() has confirmed the
-- program is error-free, so it can assume all tokens are valid.

local function compile(memory, labels)
    local compiled = {}
    for _, line in ipairs(memory) do
        local tokens = tokenize(line)
        if #tokens == 0 then
            -- blank or label-only line
            table.insert(compiled, { op = "NOP" })
        else
            local mnemonic = tokens[1]:upper()
            local rec = { op = mnemonic }
            -- Resolve each argument to its most efficient runtime form
            local desc = INSTR[mnemonic]
            if desc then
                for i, arg_type in ipairs(desc[2]) do
                    local raw = tokens[i + 1]
                    if arg_type == "imm" then
                        rec["a"..i] = tonumber(raw)      -- number
                    elseif arg_type == "lbl" then
                        rec["a"..i] = labels[raw]        -- line number (integer)
                    elseif arg_type == "reg_or_imm" then
                        -- WAIT: store number if immediate, string if register
                        rec["a"..i] = tonumber(raw) or raw
                    else
                        rec["a"..i] = raw                -- register name or signal name (string)
                    end
                end
            end
            table.insert(compiled, rec)
        end
    end
    return compiled
end

-- ── Dispatch table ────────────────────────────────────────────────────────────
--
-- Each entry is a function(cpu, rec) where rec is the compiled instruction
-- record. Returns true if the instruction_pointer should NOT be advanced
-- (i.e. the instruction handled IP itself, or halted/errored).
-- Returns nil/false to advance normally.

local DISPATCH = {}

DISPATCH["HLT"] = function(cpu, _)
    cpu.status.is_halted = true
    return true
end

DISPATCH["NOP"] = function() end

DISPATCH["LI"] = function(cpu, rec)
    if rec.a1 ~= "x0" then cpu.registers[rec.a1] = rec.a2 end
end

DISPATCH["ADDI"] = function(cpu, rec)
    if rec.a1 ~= "x0" then
        cpu.registers[rec.a1] = cpu.registers[rec.a2] + rec.a3
    end
end

DISPATCH["ADD"] = function(cpu, rec)
    if rec.a1 ~= "x0" then
        cpu.registers[rec.a1] = cpu.registers[rec.a2] + cpu.registers[rec.a3]
    end
end

DISPATCH["SUB"] = function(cpu, rec)
    if rec.a1 ~= "x0" then
        cpu.registers[rec.a1] = cpu.registers[rec.a2] - cpu.registers[rec.a3]
    end
end

DISPATCH["MUL"] = function(cpu, rec)
    if rec.a1 ~= "x0" then
        cpu.registers[rec.a1] = cpu.registers[rec.a2] * cpu.registers[rec.a3]
    end
end

DISPATCH["MULI"] = function(cpu, rec)
    if rec.a1 ~= "x0" then
        cpu.registers[rec.a1] = cpu.registers[rec.a2] * rec.a3
    end
end

DISPATCH["DIV"] = function(cpu, rec)
    if rec.a1 ~= "x0" then
        local rt = cpu.registers[rec.a3]
        if rt == 0 then
            cpu.status.error = true
            table.insert(cpu.errors, "[DIV:" .. cpu.instruction_pointer .. "] Division by zero")
            return true
        end
        cpu.registers[rec.a1] = math.floor(cpu.registers[rec.a2] / rt)
    end
end

DISPATCH["DIVI"] = function(cpu, rec)
    if rec.a1 ~= "x0" then
        if rec.a3 == 0 then
            cpu.status.error = true
            table.insert(cpu.errors, "[DIVI:" .. cpu.instruction_pointer .. "] Division by zero")
            return true
        end
        cpu.registers[rec.a1] = math.floor(cpu.registers[rec.a2] / rec.a3)
    end
end

DISPATCH["REM"] = function(cpu, rec)
    if rec.a1 ~= "x0" then
        local rt = cpu.registers[rec.a3]
        if rt == 0 then
            cpu.status.error = true
            table.insert(cpu.errors, "[REM:" .. cpu.instruction_pointer .. "] Division by zero")
            return true
        end
        cpu.registers[rec.a1] = math.fmod(cpu.registers[rec.a2], rt)
    end
end

DISPATCH["REMI"] = function(cpu, rec)
    if rec.a1 ~= "x0" then
        if rec.a3 == 0 then
            cpu.status.error = true
            table.insert(cpu.errors, "[REMI:" .. cpu.instruction_pointer .. "] Division by zero")
            return true
        end
        cpu.registers[rec.a1] = math.fmod(cpu.registers[rec.a2], rec.a3)
    end
end

DISPATCH["SLT"] = function(cpu, rec)
    if rec.a1 ~= "x0" then
        cpu.registers[rec.a1] = (cpu.registers[rec.a2] < cpu.registers[rec.a3]) and 1 or 0
    end
end

DISPATCH["SLTI"] = function(cpu, rec)
    if rec.a1 ~= "x0" then
        cpu.registers[rec.a1] = (cpu.registers[rec.a2] < rec.a3) and 1 or 0
    end
end

DISPATCH["AND"] = function(cpu, rec)
    if rec.a1 ~= "x0" then
        cpu.registers[rec.a1] = _band(cpu.registers[rec.a2], cpu.registers[rec.a3])
    end
end

DISPATCH["OR"] = function(cpu, rec)
    if rec.a1 ~= "x0" then
        cpu.registers[rec.a1] = _bor(cpu.registers[rec.a2], cpu.registers[rec.a3])
    end
end

DISPATCH["XOR"] = function(cpu, rec)
    if rec.a1 ~= "x0" then
        cpu.registers[rec.a1] = _bxor(cpu.registers[rec.a2], cpu.registers[rec.a3])
    end
end

DISPATCH["NOT"] = function(cpu, rec)
    if rec.a1 ~= "x0" then
        cpu.registers[rec.a1] = _bnot(cpu.registers[rec.a2])
    end
end

DISPATCH["SLL"] = function(cpu, rec)
    if rec.a1 ~= "x0" then
        cpu.registers[rec.a1] = _lshift(cpu.registers[rec.a2], cpu.registers[rec.a3])
    end
end

DISPATCH["SLLI"] = function(cpu, rec)
    if rec.a1 ~= "x0" then
        cpu.registers[rec.a1] = _lshift(cpu.registers[rec.a2], rec.a3)
    end
end

DISPATCH["SRL"] = function(cpu, rec)
    if rec.a1 ~= "x0" then
        cpu.registers[rec.a1] = _rshift(cpu.registers[rec.a2], cpu.registers[rec.a3])
    end
end

DISPATCH["SRLI"] = function(cpu, rec)
    if rec.a1 ~= "x0" then
        cpu.registers[rec.a1] = _rshift(cpu.registers[rec.a2], rec.a3)
    end
end

DISPATCH["SRA"] = function(cpu, rec)
    if rec.a1 ~= "x0" then
        cpu.registers[rec.a1] = _arshift(cpu.registers[rec.a2], cpu.registers[rec.a3])
    end
end

DISPATCH["SRAI"] = function(cpu, rec)
    if rec.a1 ~= "x0" then
        cpu.registers[rec.a1] = _arshift(cpu.registers[rec.a2], rec.a3)
    end
end

DISPATCH["WAIT"] = function(cpu, rec)
    local a1 = rec.a1
    if cpu.status.wait_cycles == nil then
        local val = type(a1) == "number" and a1 or cpu.registers[a1]
        cpu.status.wait_cycles = val - 1
        return true   -- do not advance IP
    elseif cpu.status.wait_cycles > 1 then
        cpu.status.wait_cycles = cpu.status.wait_cycles - 1
        return true
    else
        cpu.status.wait_cycles = nil
        -- fall through; advance IP normally
    end
end

DISPATCH["WSIG"] = function(cpu, rec)
    cpu.registers[rec.a1] = { name = rec.a2, count = cpu.registers[rec.a3] }
end

DISPATCH["WSIGI"] = function(cpu, rec)
    cpu.registers[rec.a1] = { name = rec.a2, count = rec.a3 }
end

DISPATCH["JAL"] = function(cpu, rec)
    if rec.a1 ~= "x0" then
        cpu.registers[rec.a1] = cpu.instruction_pointer + 1
    end
    cpu.instruction_pointer = rec.a2   -- already resolved to line number
    cpu.status.jump_executed = true
    return true
end

DISPATCH["JR"] = function(cpu, rec)
    local rs = cpu.registers[rec.a1]
    local target = (rs == 0) and 1 or rs
    if target < 1 or target > #cpu.compiled then
        cpu.status.error = true
        table.insert(cpu.errors,
            "[JR:" .. cpu.instruction_pointer .. "] Return address out of range: " .. target)
        return true
    end
    cpu.instruction_pointer = target
    cpu.status.jump_executed = true
    return true
end

DISPATCH["BEQ"] = function(cpu, rec)
    if cpu.registers[rec.a1] == cpu.registers[rec.a2] then
        cpu.instruction_pointer = rec.a3
        cpu.status.jump_executed = true
        return true
    end
end

DISPATCH["BNE"] = function(cpu, rec)
    if cpu.registers[rec.a1] ~= cpu.registers[rec.a2] then
        cpu.instruction_pointer = rec.a3
        cpu.status.jump_executed = true
        return true
    end
end

DISPATCH["BLT"] = function(cpu, rec)
    if cpu.registers[rec.a1] < cpu.registers[rec.a2] then
        cpu.instruction_pointer = rec.a3
        cpu.status.jump_executed = true
        return true
    end
end

DISPATCH["BLE"] = function(cpu, rec)
    if cpu.registers[rec.a1] <= cpu.registers[rec.a2] then
        cpu.instruction_pointer = rec.a3
        cpu.status.jump_executed = true
        return true
    end
end

DISPATCH["BGT"] = function(cpu, rec)
    if cpu.registers[rec.a1] > cpu.registers[rec.a2] then
        cpu.instruction_pointer = rec.a3
        cpu.status.jump_executed = true
        return true
    end
end

DISPATCH["BGE"] = function(cpu, rec)
    if cpu.registers[rec.a1] >= cpu.registers[rec.a2] then
        cpu.instruction_pointer = rec.a3
        cpu.status.jump_executed = true
        return true
    end
end

DISPATCH["BEQI"] = function(cpu, rec)
    if cpu.registers[rec.a1] == rec.a2 then
        cpu.instruction_pointer = rec.a3
        cpu.status.jump_executed = true
        return true
    end
end

DISPATCH["BNEI"] = function(cpu, rec)
    if cpu.registers[rec.a1] ~= rec.a2 then
        cpu.instruction_pointer = rec.a3
        cpu.status.jump_executed = true
        return true
    end
end

DISPATCH["BLTI"] = function(cpu, rec)
    if cpu.registers[rec.a1] < rec.a2 then
        cpu.instruction_pointer = rec.a3
        cpu.status.jump_executed = true
        return true
    end
end

DISPATCH["BLEI"] = function(cpu, rec)
    if cpu.registers[rec.a1] <= rec.a2 then
        cpu.instruction_pointer = rec.a3
        cpu.status.jump_executed = true
        return true
    end
end

DISPATCH["BGTI"] = function(cpu, rec)
    if cpu.registers[rec.a1] > rec.a2 then
        cpu.instruction_pointer = rec.a3
        cpu.status.jump_executed = true
        return true
    end
end

DISPATCH["BGEI"] = function(cpu, rec)
    if cpu.registers[rec.a1] >= rec.a2 then
        cpu.instruction_pointer = rec.a3
        cpu.status.jump_executed = true
        return true
    end
end

DISPATCH["RSIG"] = function(cpu, rec)
    if rec.a1 ~= "x0" then
        cpu.registers[rec.a1] = (cpu.input_signals.red[rec.a2]   or 0)
                               + (cpu.input_signals.green[rec.a2] or 0)
    end
end

DISPATCH["RSIGR"] = function(cpu, rec)
    if rec.a1 ~= "x0" then
        cpu.registers[rec.a1] = cpu.input_signals.red[rec.a2] or 0
    end
end

DISPATCH["RSIGG"] = function(cpu, rec)
    if rec.a1 ~= "x0" then
        cpu.registers[rec.a1] = cpu.input_signals.green[rec.a2] or 0
    end
end

DISPATCH["CNTSR"] = function(cpu, rec)
    if rec.a1 ~= "x0" then
        local count = 0
        for _ in pairs(cpu.input_signals.red) do count = count + 1 end
        cpu.registers[rec.a1] = count
    end
end

DISPATCH["CNTSG"] = function(cpu, rec)
    if rec.a1 ~= "x0" then
        local count = 0
        for _ in pairs(cpu.input_signals.green) do count = count + 1 end
        cpu.registers[rec.a1] = count
    end
end

-- ── CPU lifecycle ─────────────────────────────────────────────────────────────

local function apply_validation_and_compile(cpu_state, memory)
    local errs = module.validate_program(memory)
    for _, e in ipairs(errs) do
        table.insert(cpu_state.errors, e)
    end
    if #errs > 0 then
        cpu_state.status.error = true
        cpu_state.compiled = {}
    else
        cpu_state.compiled = compile(memory, cpu_state.labels)
    end
end

function module.new(code)
    local cpuClass = setmetatable({}, module)
    cpuClass.status = { is_halted = false, jump_executed = false, error = false }
    cpuClass.registers = {}
    for i = 0, 31 do cpuClass.registers["x" .. i] = 0 end
    for i = 0, 3  do cpuClass.registers["o" .. i] = { name = nil, count = 0 } end
    local memory = code or { "HLT" }
    cpuClass.memory              = memory
    cpuClass.instruction_pointer = 1
    cpuClass.labels              = module.parse_labels(memory)
    cpuClass.errors              = {}
    cpuClass.input_signals       = { red = {}, green = {} }
    cpuClass.compiled            = {}
    apply_validation_and_compile(cpuClass, memory)
    return cpuClass
end

function module:get_errors()
    return self.errors
end

function module:update_code(code)
    local memory = code or { "HLT" }
    self.memory              = memory
    self.labels              = module.parse_labels(memory)
    self.instruction_pointer = 1
    for i = 0, 31 do self.registers["x" .. i] = 0 end
    for i = 0, 3  do self.registers["o" .. i] = { name = nil, count = 0 } end
    self.status        = { is_halted = false, jump_executed = false, error = false }
    self.errors        = {}
    self.input_signals = { red = {}, green = {} }
    self.compiled      = {}
    apply_validation_and_compile(self, memory)
end

function module:get_code()
    return self.memory
end

-- ── Instruction execution ─────────────────────────────────────────────────────
--
-- Hot path. Per tick per combinator. Optimised for minimum work:
--   1. Bounds check on instruction pointer
--   2. One table index into compiled[]
--   3. One table index into DISPATCH[]
--   4. One function call
--   5. IP advance (or not, if handler returned true)
--
-- No string operations, no tonumber(), no argument count checks.

function module:step()
    if self.status.is_halted or self.status.error then return end

    local ip = self.instruction_pointer
    if self.compiled == nil then
        apply_validation_and_compile(self, self.memory)
    end
    local rec = self.compiled[ip]
    if rec == nil then
        self.status.error = true
        table.insert(self.errors, "No instruction at line " .. ip)
        return
    end

    local handler = DISPATCH[rec.op]
    if handler == nil then
        -- Should never happen after validation, but guard anyway
        self.status.error = true
        table.insert(self.errors, "No handler for instruction: " .. rec.op)
        return
    end

    local handled_ip = handler(self, rec)

    if not handled_ip then
        -- Normal advance
        self.instruction_pointer = (ip % #self.compiled) + 1
    elseif self.status.jump_executed then
        self.status.jump_executed = false
    end
    -- If handled_ip is true but jump_executed is false, IP was already set
    -- by the handler (e.g. WAIT keeping the same line) — do nothing.
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
