local minus = require("scripts.items.trinkets._minus_common")

-- C - : luck +4, tears +2.0; specials = { normal = {4, 2.0} }
minus.registerTrinket({
	name = "C -",
	luckAdd = 4,
	tearsAdd = 2.0,
})

return true