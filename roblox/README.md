# Change Role UI (Roblox)

Copy each file into Roblox Studio as the type and location shown:

| File | Type | Where |
|------|------|-------|
| `ReplicatedStorage/MarineConfig.lua` | ModuleScript, named `MarineConfig` | ReplicatedStorage |
| `ServerScriptService/RoleServer.server.lua` | Script, named `RoleServer` | ServerScriptService |
| `StarterPlayerScripts/ChangeRoleUI.client.lua` | LocalScript, named `ChangeRoleUI` | StarterPlayer > StarterPlayerScripts |

Paste each file's contents into the matching script. Nothing else is needed: the UI is built in code and the RemoteEvent is created by the server script.

Customise units, ranks, badges, colours and name lists in `MarineConfig`.

## Look
The UI uses a dark red and gold theme with a "Role Select" panel and horizontally scrolling cards. Each card shows the unit name and a big emblem. Upload your own emblem images to Roblox and set `BadgeImage = "rbxassetid://ID"` on a unit in `MarineConfig`; without one, a symbol is shown.
