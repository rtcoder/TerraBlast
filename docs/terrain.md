# Terrain

Voxel worlds store material IDs and health in packed arrays, split into 16×16×16 chunks for rendering and snapshots. Each nonempty chunk has one mesh containing exposed faces; empty chunks have no visible mesh. There is no node per voxel.

`ArenaGenerator.generate(path)` validates and constructs world/materials/typed `SpawnPoint` values without rendering. `MatchFactory.create_match(player_limit, map_path)` builds authoritative players and rules. `VoxelWorldNode.set_world` receives the generated world. TOML declares dimensions, boxes, carves and team spawns; validation checks finite numeric fields, bounds, known materials, distinct slots, clearance and support.

Available maps are `twin_forts.toml` and `two_islands.toml`. Use `--map twin_forts` or `--map two_islands` for local play, a server or headless simulation. Both support up to ten hot-seat players. The network match uses two players.

Explosions damage voxels in a block sphere, attenuated by distance and material blast resistance. Indestructible metal survives. Normal synchronization sends final material/health deltas. Initial join and recovery use self-describing chunk snapshots and a terrain checksum; clients publish the staged world only after validating the complete transfer.

After a delta, the renderer rebuilds the containing chunk plus only face-adjacent chunks across a touched boundary. A corner can dirty several neighbours; an interior voxel cannot. Debug counters expose last dirty count, last rebuilt count and current nonempty mesh count. F1 displays these counters in local play.

Unsupported pawns settle onto surviving solid terrain or are eliminated if there is no support. Pawn movement and knockback use swept voxel collision with head clearance. Terrain itself does not collapse: unsupported voxel structures remain until damaged. No smooth surfaces, rubble physics or greedy meshing are implemented.
