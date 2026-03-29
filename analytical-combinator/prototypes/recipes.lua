local analytical_combinator_recipe = {
	type = "recipe",
	name = "analytical-combinator",
	ingredients = {
		{ type = "item", name = "decider-combinator", amount = 1 },
		{ type = "item", name = "advanced-circuit", amount = 2 },
		{ type = "item", name = "iron-plate", amount = 2 },
	},
	enabled = false,
	results = { {
		type = "item",
		name = "analytical-combinator",
		amount = 1,
	} },
}

data:extend({
	analytical_combinator_recipe,
})
