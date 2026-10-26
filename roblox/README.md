# Change Role UI (Roblox)

Copy each file into Roblox Studio as the type and location shown:

| File | Type | Where |
|------|------|-------|
| `ReplicatedStorage/MarineConfig.lua` | ModuleScript, named `MarineConfig` | ReplicatedStorage |
| `ServerScriptService/RoleServer.server.lua` | Script, named `RoleServer` | ServerScriptService |
| `StarterPlayerScripts/ChangeRoleUI.client.lua` | LocalScript, named `ChangeRoleUI` | StarterPlayer > StarterPlayerScripts |

Paste each file's contents into the matching script. Nothing else is needed: the UI is built in code and the RemoteEvent is created by the server script.

Customise units, ranks, badges, colours and name lists in `MarineConfig`.
