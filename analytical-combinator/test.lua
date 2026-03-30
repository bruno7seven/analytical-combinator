require("busted.runner")()

local cpu = require("script.cpu")

describe("CPU tests", function()
    it("can advance the instruction pointer", function()
        local code = {
            "ADDI x10, x0, 1",
            "ADDI x10, x10, 2",
            "ADDI x10, x10, 3",
        }
        local myCpu = cpu.new(code)

        assert.is_true(myCpu.instruction_pointer == 1)
        myCpu:advance_ip()
        myCpu:advance_ip()
        myCpu:advance_ip()
        myCpu:advance_ip()
        assert.is_true(myCpu.instruction_pointer == 2)
        myCpu:advance_ip()
        assert.is_true(myCpu.instruction_pointer == 3)
    end)

    it("can halt", function()
        local myCpu = cpu.new({ "HLT" })
        myCpu:step()
        assert.is_true(myCpu:is_halted())

        myCpu = cpu.new()
        myCpu:step()
        assert.is_true(myCpu:is_halted())
    end)

    it("can wait on immediate value", function()
        local code = {
            "WAIT 3",
            "ADDI x10, x0, 13",
            "HLT",
        }

        local myCpu = cpu.new(code)

        for _ = 1, 3 do
            myCpu:step()
        end

        local first_result = myCpu:get_register("x10")
        myCpu:step()
        local second_result = myCpu:get_register("x10")
        myCpu:step()

        assert.are.equal(first_result, 0)
        assert.are.equal(second_result, 13)
        assert.is_true(myCpu:is_halted())
    end)

    it("can wait on register", function()
        local code = {
            "ADDI x10, x0, 3",
            "WAIT x10",
            "ADDI x11, x0, 13",
            "HLT",
        }

        local myCpu = cpu.new(code)

        for _ = 1, 4 do
            myCpu:step()
        end

        local x10 = myCpu:get_register("x10")
        local first_result = myCpu:get_register("x11")
        myCpu:step()
        local second_result = myCpu:get_register("x11")
        myCpu:step()

        assert.are.equal(x10, 3)
        assert.are.equal(first_result, 0)
        assert.are.equal(second_result, 13)
        assert.is_true(myCpu:is_halted())
    end)

    it("can write signal to output register", function()
        local test_code = {
            "main:",
            "    ADDI x10, x0, 0",
            "loop:",
            "    ADDI x10, x10, 1",
            "    WSIG o1, signal-A, x10",
            "    ADDI x5, x0, 60",
            "    WAIT x5",
            "    SLTI x6, x10, 100",
            "    BNE  x6, x0, loop",
            "    JAL  x1, main",
        }
        local myCpu = cpu.new(test_code)

        for _ = 1, 5 do
            myCpu:step()
        end

        local result = myCpu:get_register("o1")
        assert.are.equal("signal-A", result.name)
        assert.are.equal(result.count, 1)
    end)

    it("can execute an immediate add and halt", function()
        local myCpu = cpu.new({ "ADDI x10, x0, 2", "HLT" })
        myCpu:step()
        local amount = myCpu:get_register("x10")

        assert.are.equal(amount, 2)
        assert.is_false(myCpu:is_halted())

        myCpu:step()
        assert.is_true(myCpu:is_halted())
    end)

    it("can execute multiple immediate adds and halt", function()
        local code = {
            "ADDI x10, x0, 1",
            "ADDI x10, x10, 2",
            "ADDI x10, x10, 3",
            "HLT",
        }
        local myCpu = cpu.new(code)

        for _ = 1, 4 do
            myCpu:step()
        end

        local result = myCpu:get_register("x10")

        assert.are.equal(6, result)
        assert.is_true(myCpu:is_halted())
    end)

    it("can execute SLT (set if less than)", function()
        local code = {
            "ADDI x10, x0, 10",
            "ADDI x11, x0, 11",
            "SLT x12, x10, x11",
            "HLT",
        }
        local myCpu = cpu.new(code)

        while not myCpu:is_halted() do
            myCpu:step()
        end

        local result = myCpu:get_register("x12")
        assert.are.equal(1, result)
    end)

    it("can execute SLTI (set if less than immediate value)", function()
        local code = {
            "ADDI x10, x0, 10",
            "ADDI x11, x0, 11",
            "SLTI x12, x10, 11",
            "HLT",
        }
        local myCpu = cpu.new(code)

        while not myCpu:is_halted() do
            myCpu:step()
        end

        local result = myCpu:get_register("x12")
        assert.are.equal(1, result)
    end)

    it("can execute subtracts", function()
        local code = {
            "ADDI x10, x0, 0",
            "ADDI x11, x0, 3",
            "SUB x10, x10, x11",
            "SUB x10, x10, x11",
            "HLT",
        }
        local myCpu = cpu.new(code)

        while not myCpu:is_halted() do
            myCpu:step()
        end

        local result = myCpu:get_register("x10")

        assert.are.equal(-6, result)
        assert.is_true(myCpu:is_halted())
    end)

    it("can ADD two registers", function()
        local code = {
            "ADDI x10, x0, 37",
            "ADDI x11, x0, 25",
            "ADD  x12, x10, x11",
            "HLT",
        }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end

        assert.are.equal(62, myCpu:get_register("x12"))
        assert.is_true(myCpu:is_halted())
    end)

    it("ADD accumulates in place", function()
        local code = {
            "ADDI x10, x0, 10",
            "ADDI x11, x0, 5",
            "ADD  x10, x10, x11",   -- x10 = 10 + 5
            "ADD  x10, x10, x11",   -- x10 = 15 + 5
            "HLT",
        }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end

        assert.are.equal(20, myCpu:get_register("x10"))
    end)

    it("ADD write to x0 is silently ignored", function()
        local code = {
            "ADDI x10, x0, 7",
            "ADD  x0, x10, x10",
            "HLT",
        }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end

        assert.are.equal(0, myCpu:get_register("x0"))
        assert.is_false(myCpu.status.error)
    end)

    it("ADD handles negative values", function()
        local code = {
            "ADDI x10, x0, -12",
            "ADDI x11, x0, 5",
            "ADD  x12, x10, x11",
            "HLT",
        }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end

        assert.are.equal(-7, myCpu:get_register("x12"))
    end)

    it("ADD with invalid register sets error", function()
        local myCpu = cpu.new({ "ADD x1, x99, x0" })
        myCpu:step()
        assert.is_true(myCpu.status.error)
        assert.are.equal(1, #myCpu:get_errors())
    end)

    it("ADD with wrong arg count sets error", function()
        local myCpu = cpu.new({ "ADD x1, x0" })
        myCpu:step()
        assert.is_true(myCpu.status.error)
    end)

    it("can get label name from source code line", function()
        local test_lines = {
            { input = "main:",              expected = "main" },
            { input = "  loop:",            expected = "loop" },
            { input = "    main:",          expected = "main" },
            { input = "start_func:",        expected = "start_func" },
            { input = "  inner_loop: NOP",  expected = "inner_loop" },
            { input = "label1: ADD x1, x2", expected = "label1" },
        }

        for _, test in ipairs(test_lines) do
            assert.are.equal(test.expected, cpu.extract_label_name(test.input))
        end
    end)

    it("can get labels with line number from source code", function()
        local test_code = {
            "main:",
            "    ADDI x1, x0, 10",
            "loop:",
            "    ADDI x1, x1, -1",
            "    BNE x1, x0, loop",
            "    JAL x1, main",
            "    inner: NOP",
        }
        local expected = {
            main = 1,
            loop = 3,
            inner = 7,
        }

        local results = cpu.parse_labels(test_code)
        assert.are.equal(#expected, #results)
        for key, value in pairs(results) do
            assert.are.equal(expected[key], value)
        end
    end)

    it("can JAL, leaves x0 unchanged", function()
        local test_code = {
            "main:",
            "    ADDI x10, x0, 10",
            "    JAL x0, loop3",
            "loop1:",
            "    ADDI x10, x10, 1",
            "    JAL x0, exit",
            "loop2:",
            "    ADDI x10, x10, 1",
            "    JAL x0, loop1",
            "loop3:",
            "    ADDI x10, x10, 1",
            "    JAL x0, loop2",
            "exit: HLT",
        }
        local myCpu = cpu.new(test_code)

        while not myCpu:is_halted() do
            myCpu:step()
        end

        local result = myCpu:get_register("x10")
        local x0 = myCpu:get_register("x0")

        assert.is_true(myCpu:is_halted())
        assert.are.equal(result, 13)
        assert.are.equal(x0, 0)
    end)

    it("can JAL, store return address in register", function()
        local test_code = {
            "main:",
            "    ADDI x10, x0, 10",
            "    JAL x1, loop3",
            "loop1:",
            "    ADDI x10, x10, 1",
            "    JAL x2, exit",
            "loop2:",
            "    ADDI x10, x10, 1",
            "    JAL x3, loop1",
            "loop3:",
            "    ADDI x10, x10, 1",
            "    JAL x4, loop2",
            "exit: HLT",
        }
        local myCpu = cpu.new(test_code)

        while not myCpu:is_halted() do
            myCpu:step()
        end

        local result = myCpu:get_register("x10")
        local x1 = myCpu:get_register("x1")
        local x2 = myCpu:get_register("x2")
        local x3 = myCpu:get_register("x3")
        local x4 = myCpu:get_register("x4")

        assert.is_true(myCpu:is_halted())
        assert.are.equal(result, 13)
        assert.are.equal(x1, 4)
        assert.are.equal(x2, 7)
        assert.are.equal(x3, 10)
        assert.are.equal(x4, 13)
    end)

    it("can BEQ (branch if equal)", function()
        local test_code = {
            "main:",
            "    ADDI x10, x0, 9",
            "    ADDI x11, x0, 9",
            "    BEQ x10, x11, loop1",
            "loop1:",
            "    ADDI x12, x0, 13",
            "    BEQ x10, x12, main",
            "exit: HLT",
        }
        local myCpu = cpu.new(test_code)

        while not myCpu:is_halted() do
            myCpu:step()
        end

        local x10 = myCpu:get_register("x10")
        local x11 = myCpu:get_register("x11")
        local x12 = myCpu:get_register("x12")

        assert.is_true(myCpu:is_halted())
        assert.are.equal(x10, 9)
        assert.are.equal(x11, 9)
        assert.are.equal(x12, 13)
    end)

    it("can BNE (branch not equal)", function()
        local test_code = {
            "main:",
            "    ADDI x10, x0, 9",
            "    ADDI x11, x0, 9",
            "    BNE x10, x11, loop2",
            "loop1:",
            "    ADDI x12, x0, 13",
            "    BNE x10, x12, exit",
            "loop2:",
            "    ADDI x12, x12, 13",
            "exit: HLT",
        }
        local myCpu = cpu.new(test_code)

        while not myCpu:is_halted() do
            myCpu:step()
        end

        local x10 = myCpu:get_register("x10")
        local x11 = myCpu:get_register("x11")
        local x12 = myCpu:get_register("x12")

        assert.is_true(myCpu:is_halted())
        assert.are.equal(x10, 9)
        assert.are.equal(x11, 9)
        assert.are.equal(x12, 13)
    end)

    it("can report a runtime error", function()
        local test_code = { "ASDF x0, x0, 1" }

        local myCpu = cpu.new(test_code)
        myCpu:step()

        local errors = myCpu:get_errors()
        assert.are.equal(1, #errors)

        local error = errors[1]
        local contains_invalid_instruction = nil ~= string.match(error, "ASDF")
        assert.is_true(contains_invalid_instruction)
    end)

    it("can't step further after runtime error", function()
        local test_code = {
            "ASDF x0, x0, 1",
            "ADDI x1, x0, 13",
            "HLT"
        }

        local myCpu = cpu.new(test_code)
        myCpu:step()
        myCpu:step()

        local errors = myCpu:get_errors()
        assert.are.equal(1, #errors)

        local error = errors[1]
        local contains_invalid_instruction = nil ~= string.match(error, "ASDF")
        assert.is_true(contains_invalid_instruction)

        assert.are.equal(1, myCpu.instruction_pointer)
    end)

    -- Tests for inputs that crash the state machine.
    -- These should set the error status instead of raising Lua errors.

    it("handles empty code table without crashing", function()
        local myCpu = cpu.new({})
        assert.has_no.errors(function() myCpu:step() end)
        assert.is_true(myCpu.status.error or myCpu.status.is_halted)
    end)

    it("handles ADDI with non-numeric immediate without crashing", function()
        local myCpu = cpu.new({ "ADDI x1, x0, abc" })
        assert.has_no.errors(function() myCpu:step() end)
        assert.is_true(myCpu.status.error)
        assert.are.equal(1, #myCpu:get_errors())
    end)

    it("handles ADDI with invalid source register without crashing", function()
        local myCpu = cpu.new({ "ADDI x1, x99, 5" })
        assert.has_no.errors(function() myCpu:step() end)
        assert.is_true(myCpu.status.error)
        assert.are.equal(1, #myCpu:get_errors())
    end)

    it("handles SUB with invalid registers without crashing", function()
        local myCpu = cpu.new({ "SUB x1, x99, x0" })
        assert.has_no.errors(function() myCpu:step() end)
        assert.is_true(myCpu.status.error)
        assert.are.equal(1, #myCpu:get_errors())

        myCpu = cpu.new({ "SUB x1, x0, x99" })
        assert.has_no.errors(function() myCpu:step() end)
        assert.is_true(myCpu.status.error)
    end)

    it("handles SLT with invalid registers without crashing", function()
        local myCpu = cpu.new({ "SLT x1, x99, x0" })
        assert.has_no.errors(function() myCpu:step() end)
        assert.is_true(myCpu.status.error)
        assert.are.equal(1, #myCpu:get_errors())

        myCpu = cpu.new({ "SLT x1, x0, x99" })
        assert.has_no.errors(function() myCpu:step() end)
        assert.is_true(myCpu.status.error)
    end)

    it("handles SLTI with non-numeric immediate without crashing", function()
        local myCpu = cpu.new({ "SLTI x1, x0, abc" })
        assert.has_no.errors(function() myCpu:step() end)
        assert.is_true(myCpu.status.error)
        assert.are.equal(1, #myCpu:get_errors())
    end)

    it("handles SLTI with invalid source register without crashing", function()
        local myCpu = cpu.new({ "SLTI x1, x99, 5" })
        assert.has_no.errors(function() myCpu:step() end)
        assert.is_true(myCpu.status.error)
        assert.are.equal(1, #myCpu:get_errors())
    end)

    it("handles WAIT with non-numeric non-register arg without crashing", function()
        local myCpu = cpu.new({ "WAIT abc" })
        assert.has_no.errors(function() myCpu:step() end)
        assert.is_true(myCpu.status.error)
        assert.are.equal(1, #myCpu:get_errors())
    end)

    it("handles WSIG with no args without crashing", function()
        local myCpu = cpu.new({ "WSIG" })
        assert.has_no.errors(function() myCpu:step() end)
        assert.is_true(myCpu.status.error)
        assert.are.equal(1, #myCpu:get_errors())
    end)

    it("handles JAL to undefined label without crashing", function()
        local myCpu = cpu.new({ "JAL x0, nonexistent", "HLT" })
        assert.has_no.errors(function() myCpu:step() end)
        assert.is_true(myCpu.status.error)
        assert.are.equal(1, #myCpu:get_errors())
    end)

    it("handles BEQ to undefined label without crashing", function()
        local myCpu = cpu.new({ "BEQ x0, x0, nonexistent", "HLT" })
        assert.has_no.errors(function() myCpu:step() end)
        assert.is_true(myCpu.status.error)
        assert.are.equal(1, #myCpu:get_errors())
    end)

    it("BEQ with literal second argument sets error (not a register)", function()
        -- Regression test: BEQ x3, 0, label was silently miscompared as nil==nil
        local myCpu = cpu.new({ "BEQ x0, 0, skip", "skip: HLT" })
        myCpu:step()
        assert.is_true(myCpu.status.error)
    end)

    it("BEQ with invalid register sets error", function()
        local myCpu = cpu.new({ "BEQ x0, x99, skip", "skip: HLT" })
        myCpu:step()
        assert.is_true(myCpu.status.error)
    end)

    it("BNE with literal second argument sets error", function()
        local myCpu = cpu.new({ "BNE x0, 1, skip", "skip: HLT" })
        myCpu:step()
        assert.is_true(myCpu.status.error)
    end)

    it("WSIG with invalid source register sets error", function()
        local myCpu = cpu.new({ "WSIG o0, signal-A, x99" })
        myCpu:step()
        assert.is_true(myCpu.status.error)
    end)

    it("JAL with invalid destination register sets error", function()
        local myCpu = cpu.new({ "dest: JAL x99, dest" })
        myCpu:step()
        assert.is_true(myCpu.status.error)
    end)

    -- ── Immediate branch instructions ─────────────────────────────────────────

    it("BEQI branches when rs == immediate", function()
        local code = { "ADDI x10, x0, 42", "BEQI x10, 42, done", "ADDI x11, x0, 99", "done: HLT" }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(0, myCpu:get_register("x11"))
    end)

    it("BEQI does not branch when rs ~= immediate", function()
        local code = { "ADDI x10, x0, 41", "BEQI x10, 42, skip", "ADDI x11, x0, 7", "skip: HLT" }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(7, myCpu:get_register("x11"))
    end)

    it("BEQI accepts hex immediate", function()
        local code = { "ADDI x10, x0, 255", "BEQI x10, 0xFF, done", "ADDI x11, x0, 99", "done: HLT" }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(0, myCpu:get_register("x11"))
    end)

    it("BNEI branches when rs ~= immediate", function()
        local code = { "ADDI x10, x0, 5", "BNEI x10, 42, done", "ADDI x11, x0, 99", "done: HLT" }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(0, myCpu:get_register("x11"))
    end)

    it("BNEI does not branch when rs == immediate", function()
        local code = { "ADDI x10, x0, 42", "BNEI x10, 42, skip", "ADDI x11, x0, 7", "skip: HLT" }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(7, myCpu:get_register("x11"))
    end)

    it("BLTI branches when rs < immediate", function()
        local code = { "ADDI x10, x0, 5", "BLTI x10, 10, done", "ADDI x11, x0, 99", "done: HLT" }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(0, myCpu:get_register("x11"))
    end)

    it("BLTI does not branch when rs >= immediate", function()
        local code = { "ADDI x10, x0, 10", "BLTI x10, 10, skip", "ADDI x11, x0, 7", "skip: HLT" }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(7, myCpu:get_register("x11"))
    end)

    it("BLEI branches when rs == immediate", function()
        local code = { "ADDI x10, x0, 10", "BLEI x10, 10, done", "ADDI x11, x0, 99", "done: HLT" }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(0, myCpu:get_register("x11"))
    end)

    it("BGTI branches when rs > immediate", function()
        local code = { "ADDI x10, x0, 11", "BGTI x10, 10, done", "ADDI x11, x0, 99", "done: HLT" }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(0, myCpu:get_register("x11"))
    end)

    it("BGTI does not branch when rs == immediate", function()
        local code = { "ADDI x10, x0, 10", "BGTI x10, 10, skip", "ADDI x11, x0, 7", "skip: HLT" }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(7, myCpu:get_register("x11"))
    end)

    it("BGEI branches when rs >= immediate", function()
        local code = { "ADDI x10, x0, 10", "BGEI x10, 10, done", "ADDI x11, x0, 99", "done: HLT" }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(0, myCpu:get_register("x11"))
    end)

    it("BGEI does not branch when rs < immediate", function()
        local code = { "ADDI x10, x0, 9", "BGEI x10, 10, skip", "ADDI x11, x0, 7", "skip: HLT" }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(7, myCpu:get_register("x11"))
    end)

    it("immediate branch with invalid register sets error", function()
        local myCpu = cpu.new({ "BEQI x99, 0, skip", "skip: HLT" })
        myCpu:step()
        assert.is_true(myCpu.status.error)
    end)

    it("immediate branch with non-numeric immediate sets error", function()
        local myCpu = cpu.new({ "BEQI x0, abc, skip", "skip: HLT" })
        myCpu:step()
        assert.is_true(myCpu.status.error)
    end)

    it("BNEI used to loop: counts to 5 using immediate branch", function()
        -- Practical use: tight loop without needing a comparison register
        local code = {
            "loop:",
            "    ADDI x10, x10, 1",
            "    BNEI x10, 5, loop",
            "    HLT",
        }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(5, myCpu:get_register("x10"))
    end)

    it("handles BNE to undefined label without crashing", function()
        local myCpu = cpu.new({ "ADDI x1, x0, 1", "BNE x1, x0, nonexistent", "HLT" })
        myCpu:step()
        assert.has_no.errors(function() myCpu:step() end)
        assert.is_true(myCpu.status.error)
        assert.are.equal(1, #myCpu:get_errors())
    end)

    -- ── MUL ──────────────────────────────────────────────────────────────────

    it("MUL multiplies two registers", function()
        local code = { "ADDI x10, x0, 6", "ADDI x11, x0, 7", "MUL x12, x10, x11", "HLT" }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(42, myCpu:get_register("x12"))
    end)

    it("MUL by zero yields zero", function()
        local code = { "ADDI x10, x0, 99", "MUL x11, x10, x0", "HLT" }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(0, myCpu:get_register("x11"))
    end)

    it("MUL write to x0 silently ignored", function()
        local code = { "ADDI x10, x0, 5", "MUL x0, x10, x10", "HLT" }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(0, myCpu:get_register("x0"))
        assert.is_false(myCpu.status.error)
    end)

    it("MUL with invalid register sets error", function()
        local myCpu = cpu.new({ "MUL x1, x99, x0" })
        myCpu:step()
        assert.is_true(myCpu.status.error)
    end)

    -- ── MULI ─────────────────────────────────────────────────────────────────

    it("MULI multiplies register by immediate", function()
        local code = { "ADDI x10, x0, 6", "MULI x11, x10, 7", "HLT" }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(42, myCpu:get_register("x11"))
    end)

    it("MULI by negative immediate", function()
        local code = { "ADDI x10, x0, 5", "MULI x11, x10, -3", "HLT" }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(-15, myCpu:get_register("x11"))
    end)

    it("MULI with invalid immediate sets error", function()
        local myCpu = cpu.new({ "MULI x1, x0, abc" })
        myCpu:step()
        assert.is_true(myCpu.status.error)
    end)

    -- ── DIV ──────────────────────────────────────────────────────────────────

    it("DIV divides two registers (floor division)", function()
        local code = { "ADDI x10, x0, 17", "ADDI x11, x0, 5", "DIV x12, x10, x11", "HLT" }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(3, myCpu:get_register("x12"))
    end)

    it("DIV floors toward negative infinity for negative dividend", function()
        -- floor(-17 / 5) = floor(-3.4) = -4  (not -3 as C truncation would give)
        local code = { "ADDI x10, x0, -17", "ADDI x11, x0, 5", "DIV x12, x10, x11", "HLT" }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(-4, myCpu:get_register("x12"))
    end)

    it("DIV write to x0 silently ignored", function()
        local code = { "ADDI x10, x0, 10", "ADDI x11, x0, 2", "DIV x0, x10, x11", "HLT" }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(0, myCpu:get_register("x0"))
        assert.is_false(myCpu.status.error)
    end)

    it("DIV by zero sets error", function()
        local code = { "ADDI x10, x0, 10", "DIV x11, x10, x0", "HLT" }
        local myCpu = cpu.new(code)
        myCpu:step()
        myCpu:step()
        assert.is_true(myCpu.status.error)
        assert.are.equal(1, #myCpu:get_errors())
    end)

    it("DIV with invalid register sets error", function()
        local myCpu = cpu.new({ "DIV x1, x99, x0" })
        myCpu:step()
        assert.is_true(myCpu.status.error)
    end)

    -- ── DIVI ─────────────────────────────────────────────────────────────────

    it("DIVI divides register by immediate", function()
        local code = { "ADDI x10, x0, 100", "DIVI x11, x10, 7", "HLT" }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(14, myCpu:get_register("x11"))
    end)

    it("DIVI by zero sets error", function()
        local myCpu = cpu.new({ "ADDI x10, x0, 5", "DIVI x11, x10, 0" })
        myCpu:step()
        myCpu:step()
        assert.is_true(myCpu.status.error)
    end)

    it("DIVI with hex immediate", function()
        -- 256 / 0x10 = 256 / 16 = 16
        local code = { "ADDI x10, x0, 256", "DIVI x11, x10, 0x10", "HLT" }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(16, myCpu:get_register("x11"))
    end)

    -- ── REM ──────────────────────────────────────────────────────────────────

    it("REM returns remainder (sign matches dividend)", function()
        local code = { "ADDI x10, x0, 17", "ADDI x11, x0, 5", "REM x12, x10, x11", "HLT" }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(2, myCpu:get_register("x12"))
    end)

    it("REM with negative dividend gives negative remainder (C-style)", function()
        -- fmod(-17, 5) = -2  (sign follows dividend, same as C %)
        local code = { "ADDI x10, x0, -17", "ADDI x11, x0, 5", "REM x12, x10, x11", "HLT" }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(-2, myCpu:get_register("x12"))
    end)

    it("REM useful for modulo / wrap-around", function()
        -- Use REM to keep a counter in range 0..7 (3 bits)
        local code = {
            "ADDI x10, x0, 25",   -- some value
            "ADDI x11, x0, 8",
            "REM  x12, x10, x11", -- x12 = 25 mod 8 = 1
            "HLT",
        }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(1, myCpu:get_register("x12"))
    end)

    it("REM by zero sets error", function()
        local code = { "ADDI x10, x0, 10", "REM x11, x10, x0", "HLT" }
        local myCpu = cpu.new(code)
        myCpu:step()
        myCpu:step()
        assert.is_true(myCpu.status.error)
    end)

    -- ── REMI ─────────────────────────────────────────────────────────────────

    it("REMI returns remainder against immediate", function()
        local code = { "ADDI x10, x0, 100", "REMI x11, x10, 7", "HLT" }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(2, myCpu:get_register("x11"))
    end)

    it("REMI by zero sets error", function()
        local myCpu = cpu.new({ "ADDI x10, x0, 5", "REMI x11, x10, 0" })
        myCpu:step()
        myCpu:step()
        assert.is_true(myCpu.status.error)
    end)

    it("REMI with hex immediate", function()
        -- 255 rem 0x10 = 255 rem 16 = 15
        local code = { "ADDI x10, x0, 255", "REMI x11, x10, 0x10", "HLT" }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(15, myCpu:get_register("x11"))
    end)

    -- ── AND ──────────────────────────────────────────────────────────────────

    it("AND performs bitwise AND", function()
        -- 60 = 0b111100, 15 = 0b001111, AND = 0b001100 = 12
        local code = { "ADDI x10, x0, 60", "ADDI x11, x0, 15", "AND x12, x10, x11", "HLT" }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(12, myCpu:get_register("x12"))
    end)

    it("AND can mask low nibble", function()
        local code = { "ADDI x10, x0, 255", "ADDI x11, x0, 15", "AND x12, x10, x11", "HLT" }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(15, myCpu:get_register("x12"))
    end)

    -- ── OR ───────────────────────────────────────────────────────────────────

    it("OR performs bitwise OR", function()
        -- 60 = 0b111100, 15 = 0b001111, OR = 0b111111 = 63
        local code = { "ADDI x10, x0, 60", "ADDI x11, x0, 15", "OR x12, x10, x11", "HLT" }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(63, myCpu:get_register("x12"))
    end)

    it("OR with zero is identity", function()
        local code = { "ADDI x10, x0, 42", "OR x11, x10, x0", "HLT" }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(42, myCpu:get_register("x11"))
    end)

    -- ── XOR ──────────────────────────────────────────────────────────────────

    it("XOR performs bitwise XOR", function()
        -- 60 = 0b111100, 15 = 0b001111, XOR = 0b110011 = 51
        local code = { "ADDI x10, x0, 60", "ADDI x11, x0, 15", "XOR x12, x10, x11", "HLT" }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(51, myCpu:get_register("x12"))
    end)

    it("XOR with self yields zero", function()
        local code = { "ADDI x10, x0, 12345", "XOR x10, x10, x10", "HLT" }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(0, myCpu:get_register("x10"))
    end)

    -- ── NOT ──────────────────────────────────────────────────────────────────

    it("NOT of 0 yields -1", function()
        local code = { "ADDI x10, x0, 0", "NOT x11, x10", "HLT" }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(-1, myCpu:get_register("x11"))
    end)

    it("NOT of -1 yields 0", function()
        local code = { "ADDI x10, x0, -1", "NOT x11, x10", "HLT" }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(0, myCpu:get_register("x11"))
    end)

    it("NOT with wrong arg count sets error", function()
        local myCpu = cpu.new({ "NOT x1, x0, x0" })
        myCpu:step()
        assert.is_true(myCpu.status.error)
    end)

    -- ── SHL / SHLI ───────────────────────────────────────────────────────────

    it("SLLI shifts left by immediate", function()
        -- 1 << 4 = 16 (logical)
        local code = { "ADDI x10, x0, 1", "SLLI x11, x10, 4", "HLT" }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(16, myCpu:get_register("x11"))
    end)

    it("SLL shifts left by register", function()
        -- 3 << 3 = 24 (logical)
        local code = { "ADDI x10, x0, 3", "ADDI x11, x0, 3", "SLL x12, x10, x11", "HLT" }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(24, myCpu:get_register("x12"))
    end)

    it("SLLI with invalid immediate sets error", function()
        local myCpu = cpu.new({ "SLLI x1, x0, abc" })
        myCpu:step()
        assert.is_true(myCpu.status.error)
    end)

    -- ── SHR / SHRI ───────────────────────────────────────────────────────────

    it("SRAI shifts right by immediate", function()
        -- 256 >> 4 = 16 (arithmetic, positive so same as logical)
        local code = { "ADDI x10, x0, 256", "SRAI x11, x10, 4", "HLT" }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(16, myCpu:get_register("x11"))
    end)

    it("SRA shifts right by register", function()
        -- 128 >> 3 = 16 (arithmetic, positive so same as logical)
        local code = { "ADDI x10, x0, 128", "ADDI x11, x0, 3", "SRA x12, x10, x11", "HLT" }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(16, myCpu:get_register("x12"))
    end)

    it("SRAI with invalid immediate sets error", function()
        local myCpu = cpu.new({ "SRAI x1, x0, abc" })
        myCpu:step()
        assert.is_true(myCpu.status.error)
    end)

    -- ── SRL / SRLI (logical right shift — zero fill) ────────────────────────────

    it("SRLI shifts right logical by immediate (zero-fills, no sign extension)", function()
        -- 0x80000000 (most-negative 32-bit) >> 1 logical = 0x40000000
        -- arithmetic would give 0xC0000000 (sign-extended)
        local code = {
            "ADDI x10, x0, -2147483648",  -- 0x80000000
            "SRLI x11, x10, 1",
            "HLT",
        }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(1073741824, myCpu:get_register("x11"))  -- 0x40000000
    end)

    it("SRL shifts right logical by register", function()
        local code = { "ADDI x10, x0, 256", "ADDI x11, x0, 4", "SRL x12, x10, x11", "HLT" }
        -- 256 >> 4 = 16
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(16, myCpu:get_register("x12"))
    end)

    it("SRA sign-extends on right shift of negative value", function()
        -- SRA of -128 >> 1 should give -64 (sign bit preserved)
        local code = { "ADDI x10, x0, -128", "SRAI x11, x10, 1", "HLT" }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(-64, myCpu:get_register("x11"))
    end)

    it("SRLI does NOT sign-extend on right shift of negative value", function()
        -- SRL of -128 (0xFFFFFF80) >> 1 should give a large positive (zero-fill from left)
        local code = { "ADDI x10, x0, -128", "SRLI x11, x10, 1", "HLT" }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        -- result should be 0x7FFFFFC0 = 2147483584, NOT -64
        assert.are.equal(2147483584, myCpu:get_register("x11"))
    end)

    -- ── CNTSR / CNTSG ────────────────────────────────────────────────────────

    it("CNTSG counts distinct signals on green wire", function()
        local code = { "CNTSG x10", "HLT" }
        local myCpu = cpu.new(code)
        myCpu:set_input_signals({},
            { ["iron-plate"] = 100, ["copper-plate"] = 50, ["steel-plate"] = 25 })
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(3, myCpu:get_register("x10"))
    end)

    it("CNTSR counts distinct signals on red wire", function()
        local code = { "CNTSR x10", "HLT" }
        local myCpu = cpu.new(code)
        myCpu:set_input_signals({ ["signal-A"] = 1, ["signal-B"] = 1 }, {})
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(2, myCpu:get_register("x10"))
    end)

    it("CNTSG returns 0 when green wire is empty", function()
        local code = { "CNTSG x10", "HLT" }
        local myCpu = cpu.new(code)
        myCpu:set_input_signals({}, {})
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(0, myCpu:get_register("x10"))
    end)

    it("CNTSR and CNTSG are independent", function()
        local code = { "CNTSR x10", "CNTSG x11", "HLT" }
        local myCpu = cpu.new(code)
        myCpu:set_input_signals(
            { ["iron-plate"] = 1 },
            { ["iron-plate"] = 1, ["copper-plate"] = 1, ["steel-plate"] = 1 }
        )
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(1, myCpu:get_register("x10"))
        assert.are.equal(3, myCpu:get_register("x11"))
    end)

    it("CNTSG write to x0 silently ignored", function()
        local code = { "CNTSG x0", "HLT" }
        local myCpu = cpu.new(code)
        myCpu:set_input_signals({}, { ["signal-A"] = 99 })
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(0, myCpu:get_register("x0"))
        assert.is_false(myCpu.status.error)
    end)

    it("CNTSG with wrong arg count sets error", function()
        local myCpu = cpu.new({ "CNTSG" })
        myCpu:step()
        assert.is_true(myCpu.status.error)
    end)

    -- ── BLT ──────────────────────────────────────────────────────────────────

    it("BLT branches when rs < rt", function()
        local code = {
            "ADDI x10, x0, 5",
            "ADDI x11, x0, 10",
            "BLT  x10, x11, done",
            "ADDI x12, x0, 99",   -- should be skipped
            "done: HLT",
        }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(0, myCpu:get_register("x12"))
    end)

    it("BLT does not branch when rs >= rt", function()
        local code = {
            "ADDI x10, x0, 10",
            "ADDI x11, x0, 10",
            "BLT  x10, x11, skip",
            "ADDI x12, x0, 42",
            "skip: HLT",
        }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(42, myCpu:get_register("x12"))
    end)

    -- ── BLE ──────────────────────────────────────────────────────────────────

    it("BLE branches when rs < rt", function()
        local code = {
            "ADDI x10, x0, 4",
            "ADDI x11, x0, 5",
            "BLE  x10, x11, done",
            "ADDI x12, x0, 99",
            "done: HLT",
        }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(0, myCpu:get_register("x12"))
    end)

    it("BLE branches when rs == rt", function()
        local code = {
            "ADDI x10, x0, 5",
            "ADDI x11, x0, 5",
            "BLE  x10, x11, done",
            "ADDI x12, x0, 99",
            "done: HLT",
        }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(0, myCpu:get_register("x12"))
    end)

    it("BLE does not branch when rs > rt", function()
        local code = {
            "ADDI x10, x0, 6",
            "ADDI x11, x0, 5",
            "BLE  x10, x11, skip",
            "ADDI x12, x0, 42",
            "skip: HLT",
        }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(42, myCpu:get_register("x12"))
    end)

    -- ── BGT ──────────────────────────────────────────────────────────────────

    it("BGT branches when rs > rt", function()
        local code = {
            "ADDI x10, x0, 10",
            "ADDI x11, x0, 5",
            "BGT  x10, x11, done",
            "ADDI x12, x0, 99",
            "done: HLT",
        }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(0, myCpu:get_register("x12"))
    end)

    it("BGT does not branch when rs == rt", function()
        local code = {
            "ADDI x10, x0, 5",
            "ADDI x11, x0, 5",
            "BGT  x10, x11, skip",
            "ADDI x12, x0, 42",
            "skip: HLT",
        }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(42, myCpu:get_register("x12"))
    end)

    -- ── BGE ──────────────────────────────────────────────────────────────────

    it("BGE branches when rs > rt", function()
        local code = {
            "ADDI x10, x0, 10",
            "ADDI x11, x0, 5",
            "BGE  x10, x11, done",
            "ADDI x12, x0, 99",
            "done: HLT",
        }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(0, myCpu:get_register("x12"))
    end)

    it("BGE branches when rs == rt", function()
        local code = {
            "ADDI x10, x0, 5",
            "ADDI x11, x0, 5",
            "BGE  x10, x11, done",
            "ADDI x12, x0, 99",
            "done: HLT",
        }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(0, myCpu:get_register("x12"))
    end)

    it("BGE does not branch when rs < rt", function()
        local code = {
            "ADDI x10, x0, 4",
            "ADDI x11, x0, 5",
            "BGE  x10, x11, skip",
            "ADDI x12, x0, 42",
            "skip: HLT",
        }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(42, myCpu:get_register("x12"))
    end)

    -- ── JR (jump register — subroutine return) ────────────────────────────────

    it("JR returns to instruction after JAL call site", function()
        -- JAL now saves IP+1 (the return address), so JR jumps directly to that value.
        local code = {
            "main:",
            "    ADDI x10, x0, 1",     -- line 2
            "    JAL  x1, my_func",    -- line 3: x1 = 4, jump to my_func
            "    ADDI x10, x10, 10",   -- line 4: resume here after return
            "    HLT",                 -- line 5
            "my_func:",
            "    ADDI x10, x10, 100",
            "    JR   x1",             -- return to line 4 directly
        }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        -- x10 = 1 + 100 (in func) + 10 (after return) = 111
        assert.are.equal(111, myCpu:get_register("x10"))
    end)

    it("JR can be used for nested calls via different registers", function()
        local code = {
            "main:",
            "    JAL  x1, add10",     -- call add10, save return in x1
            "    JAL  x2, add20",     -- call add20, save return in x2
            "    HLT",
            "add10:",
            "    ADDI x10, x10, 10",
            "    JR   x1",
            "add20:",
            "    ADDI x10, x10, 20",
            "    JR   x2",
        }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(30, myCpu:get_register("x10"))
    end)

    it("JR x0 jumps to line 1 (restart)", function()
        -- x0 is always 0; JR x0 is a special case that restarts the program
        local code = {
            "ADDI x10, x10, 1",    -- line 1: increment counter
            "SLTI x6,  x10, 3",    -- line 2: x6=1 if x10 < 3
            "BNE  x6,  x0,  loop", -- line 3: loop if not done
            "HLT",                 -- line 4
            "loop: JR x0",         -- line 5: jump to line 1
        }
        local myCpu = cpu.new(code)
        while not myCpu:is_halted() do myCpu:step() end
        assert.are.equal(3, myCpu:get_register("x10"))
    end)

    it("JR with wrong arg count sets error", function()
        local myCpu = cpu.new({ "JR x1, x2" })
        myCpu:step()
        assert.is_true(myCpu.status.error)
    end)

    it("JR with invalid register sets error", function()
        local myCpu = cpu.new({ "JR x99" })
        myCpu:step()
        assert.is_true(myCpu.status.error)
    end)

    it("JR with out-of-range return address sets error", function()
        local code = { "ADDI x1, x0, 9999", "JR x1" }
        local myCpu = cpu.new(code)
        myCpu:step()  -- ADDI
        myCpu:step()  -- JR
        assert.is_true(myCpu.status.error)
    end)

    it("branch instructions set error on undefined label", function()
        for _, instr in ipairs({ "BLT x0, x0, nowhere",
                                 "BLE x0, x0, nowhere",
                                 "BGT x0, x0, nowhere",
                                 "BGE x0, x0, nowhere" }) do
            -- Need a condition that fires: for BGT/BGE/BLT/BLE with x0,x0
            -- BGT won't fire (0 > 0 false), BLT won't fire (0 < 0 false)
            -- BLE and BGE will fire (0<=0, 0>=0 true)
        end
        -- Test BLE (fires on equal) to an undefined label
        local myCpu = cpu.new({ "BLE x0, x0, nowhere" })
        myCpu:step()
        assert.is_true(myCpu.status.error)
    end)

end)
