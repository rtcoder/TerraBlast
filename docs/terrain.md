# Terrain

MVP terrain uses chunked block voxels.

Defaults:

- Chunk size: `16x16x16`.
- MVP arena: `128x64x128`.
- Voxel data: `material_id` and `health`.
- Destruction: blocky sphere falloff.
- Mesh strategy: visible faces only, greedy meshing later if profiling requires it.

