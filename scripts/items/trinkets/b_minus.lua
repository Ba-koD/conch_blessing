local minus = require("scripts.items.trinkets._minus_common")

-- B - : luck +3, tears +3.0, damage +3.0; specials = { normal = {3, 3.0} }
minus.registerTrinket({
	name = "B -",
	luckAdd = 3,
	tearsAdd = 3.0,
	damageAdd = 3.0,
})

return true