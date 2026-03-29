flib = require("__flib__.data-util")

require("prototypes.technology")
require("prototypes.recipes")
require("prototypes.items")
require("prototypes.entities")

flib = nil

-- Font prototypes don't depend on flib
require("prototypes.fonts")
