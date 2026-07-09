# ADR-0001: Engine Godot

## Status

Accepted

## Context

TerraBlast needs a lightweight, open-source engine with fast iteration, desktop exports, later mobile support, and headless server support.

## Decision

Use Godot 4.x as the primary engine.

## Consequences

The project can prototype quickly in GDScript and export to desktop first. Server work can use Godot headless builds. Engine-specific code should stay out of pure core simulation where practical.

## Alternatives considered

Unity and Unreal were not chosen for the starting path.

