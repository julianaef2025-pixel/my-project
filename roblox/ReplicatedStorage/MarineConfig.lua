-- ModuleScript named "MarineConfig" in ReplicatedStorage
-- Edit this file to add/remove units, ranks and names.

local MarineConfig = {}

MarineConfig.Cooldown = 3          -- seconds between role changes
MarineConfig.KeepPosition = true   -- respawn where you stand instead of at the spawn point

-- Badge: a text symbol shown on the card and in the circle above the head.
-- To use your own emblem, upload an image to Roblox and add
--   BadgeImage = "rbxassetid://123456",
-- to a unit. It is then used on the card and above the head.
MarineConfig.Units = {
	{
		Id = "Instructor",
		Name = "Marine Instructor",
		Description = "Runs training and leads recruits.",
		Badge = "★",
		Color = Color3.fromRGB(212, 175, 55),
		Ranks = { "Staff Sergeant", "Gunnery Sergeant", "Master Sergeant" },
	},
	{
		Id = "DrillSergeant",
		Name = "Drill Sergeant",
		Description = "Drills, discipline and formations.",
		Badge = "✦",
		Color = Color3.fromRGB(196, 64, 64),
		Ranks = { "Sergeant", "Staff Sergeant", "Gunnery Sergeant" },
	},
	{
		Id = "Recruit",
		Name = "Marine Recruit",
		Description = "New to the academy. Time to train.",
		Badge = "●",
		Color = Color3.fromRGB(120, 160, 90),
		Ranks = { "Recruit", "Private" },
	},
	{
		Id = "Rifleman",
		Name = "Rifleman",
		Description = "Frontline infantry Marine.",
		Badge = "▲",
		Color = Color3.fromRGB(80, 130, 200),
		Ranks = { "Private First Class", "Lance Corporal", "Corporal" },
	},
	{
		Id = "Medic",
		Name = "Combat Medic",
		Description = "Keeps the squad alive.",
		Badge = "✚",
		Color = Color3.fromRGB(230, 230, 230),
		Ranks = { "Lance Corporal", "Corporal", "Sergeant" },
	},
	{
		Id = "Officer",
		Name = "Marine Officer",
		Description = "Commands units and plans missions.",
		Badge = "◆",
		Color = Color3.fromRGB(150, 90, 200),
		Ranks = { "Second Lieutenant", "First Lieutenant", "Captain" },
	},
	{
		Id = "ForceRecon",
		Name = "Force Reconnaissance",
		Description = "Elite scouts operating behind enemy lines.",
		Badge = "◉",
		Color = Color3.fromRGB(220, 60, 60),
		Ranks = { "Corporal", "Sergeant", "Staff Sergeant" },
	},
	{
		Id = "SpecOps",
		Name = "Special Operations Team",
		Description = "Specialised raids and rapid response.",
		Badge = "⚔",
		Color = Color3.fromRGB(70, 110, 200),
		Ranks = { "Sergeant", "Staff Sergeant", "Gunnery Sergeant" },
	},
	{
		Id = "Ceremonial",
		Name = "Ceremonial Guard",
		Description = "Parades, drill and honour guard duty.",
		Badge = "✪",
		Color = Color3.fromRGB(255, 205, 60),
		Ranks = { "Lance Corporal", "Corporal", "Sergeant" },
	},
}

MarineConfig.FirstNames = {
	"James", "John", "Michael", "David", "Daniel", "Ryan", "Tyler", "Jake", "Ethan", "Mason",
	"Logan", "Carter", "Owen", "Caleb", "Nathan", "Luke", "Aaron", "Dylan", "Chase", "Cole",
}

MarineConfig.LastNames = {
	"Anderson", "Brooks", "Carter", "Davis", "Evans", "Foster", "Grant", "Harris", "Jackson", "Kelly",
	"Lopez", "Miller", "Nelson", "Parker", "Reed", "Sanders", "Thompson", "Walker", "Young", "Hayes",
}

return MarineConfig
