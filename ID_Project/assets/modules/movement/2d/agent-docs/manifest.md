---
depends_on: []
conflicts_with: []
exposes: [movement/2d]
---

# movement/2d

Rapier2d movement running identical logic on both server and client (mirrors `movement` 3D).
Reads `input_movement` and writes `Velocity2d` via the shared `Movement.smooth_velocity2d`
accel/decel function, identical on both sides. Rapier2d integrates `Velocity2d` into
`Transform` on both server and client. The player spawner flags `Transform`'s `net_sync`
with `predict = true`, so the local player is reconciled by the generic `net/client/predict.lua`
layer. Remote avatars are interpolated via the `net_sync_Transform` shadow.

## Components

- `movement/2d` — Movement configuration and state. Contains:
  - `speed` (float): Speed scalar.

## Systems

### Server
| Schedule | Label | After | Purpose |
|----------|-------|-------|---------|
| First | - | - | `added { "movement/2d" }`: Set `net_sync` for client authority over `input_movement`, register input bindings |
| Update | Movement | Input | Compute desired velocity from `input_movement`, smooth via `Movement.smooth_velocity2d`, write `Velocity2d` |

### Client
| Schedule | Label | After | Purpose |
|----------|-------|-------|---------|
| First | - | - | `added { "movement/2d" }`: Register input bindings, duplicate `Transform` into `net_sync_Transform` |
| Update | Movement | Input | Mirror server logic exactly: compute + smooth velocity, write `Velocity2d` (Rapier2d integrates it into `Transform`) |
| Update | MovementInterpolation | Movement | Remote avatars only (`without net_local`): lerp/slerp `Transform` toward `net_sync_Transform` shadow. The local player is reconciled by `predict.lua` instead. |
