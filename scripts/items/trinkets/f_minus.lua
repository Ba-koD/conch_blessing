local minus = require("scripts.items.trinkets._minus_common")

-- F - : luck +5 only; specials = { normal = 5 }
minus.registerTrinket({
	name = "F -",
	luckAdd = 5,
})

return true