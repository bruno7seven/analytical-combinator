local analytical_combinator_tech = {
	type = "technology",
	name = "analytical-combinators",
	icon = "__analytical-combinator__/graphics/technology/analytical-combinator.png",
	icon_size = 256,
	effects = {
		{
			type = "unlock-recipe",
			recipe = "analytical-combinator",
		},
	},
	prerequisites = { "advanced-combinators" },
	unit = {
		count = 100,
		ingredients = {
			{ "automation-science-pack", 1 },
			{ "logistic-science-pack", 1 },
			{ "chemical-science-pack", 1 },
		},
		time = 30,
	},
	order = "a-d-d",
}

data:extend({ analytical_combinator_tech })
