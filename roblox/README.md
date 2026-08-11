# FPV Drone System (Roblox)

Walk up to a drone model, hold **E** for 1 second, and you take off in first-person FPV view. Press **X** to land/exit.

## Setup in Roblox Studio

1. **Workspace**: create a Folder named exactly `Drones` and put your drone model(s) inside it.
   - Each drone must be a **Model** with a **PrimaryPart** set (select the model → Properties → PrimaryPart → click the main body part).
   - You don't need to weld anything — the server script welds all parts to the PrimaryPart automatically.
2. **ServerScriptService**: create a **Script** and paste in `DroneServer.server.lua`.
3. **StarterPlayer → StarterPlayerScripts**: create a **LocalScript** and paste in `DroneClient.client.lua`.

## Controls (while flying)

| Input | Action |
|---|---|
| Mouse | Steer (yaw + pitch, FPV style) |
| W / S | Forward / backward |
| A / D | Strafe (drone banks into the turn) |
| Space | Ascend |
| Left Shift | Descend |
| X | Exit the drone |

## How it works

- A `ProximityPrompt` (hold E, 1s) is added to each drone's PrimaryPart.
- On entry the server freezes the pilot's character, gives the pilot **network ownership** of the drone (so flying is lag-free), and enables a `LinearVelocity` + `AlignOrientation` that the client drives every frame.
- The camera is set to Scriptable and locked to the front of the drone body for the FPV view.
- The server force-exits the pilot if they die or leave, and re-enables the prompt so someone else can fly it.

## Tuning

Top of `DroneClient.client.lua`:

- `MOVE_SPEED` — horizontal speed (studs/sec)
- `VERTICAL_SPEED` — climb/descend speed
- `MOUSE_SENSITIVITY` — steering sensitivity
- `BANK_ANGLE` — how much the drone rolls when strafing
- `CAMERA_OFFSET` — where the FPV camera sits on the drone body
