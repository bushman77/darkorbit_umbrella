# Core

Pure DarkOrbit game mechanics and the OTP world runtime. This application owns
catalog definitions, derived ship statistics, movement, live sessions, and
map processes without depending on Phoenix, Ecto, or PostgreSQL.

The umbrella's persistence application starts `Core.World.Supervisor` after
its event transport is available. Core tests can start isolated world
supervisors with injected event sinks and deterministic manual ticks.
