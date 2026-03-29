-- Define a monospace font for the assembly code editor text-box.
-- We reference the built-in "default-mono" descriptor which maps to
-- NotoMono-Regular.ttf (already bundled with Factorio core).
-- No external TTF file is needed.
data:extend({
    {
        type = "font",
        name = "ac-mono-14",
        from = "default-mono",
        size = 14,
    },
})
