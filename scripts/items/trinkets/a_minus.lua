local minus = require("scripts.items.trinkets._minus_common")

-- A - : luck +2, tears +4.0; has damage x4.0 BUT specials include only 2 and 4.0, so do not scale x4.0 by golden/box
minus.registerTrinket({
	name = "A -",
	luckAdd = 2,
	tearsAdd = 4.0,
	damageMult = 4.0,
	luckMult = 4.0,
})

return true