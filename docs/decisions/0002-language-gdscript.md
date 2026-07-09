# ADR-0002: Language GDScript

## Status

Accepted

## Context

The project needs low-friction Godot integration and mobile-aware exports.

## Decision

Use GDScript as the primary language.

## Consequences

The project favors fast iteration and simple onboarding. Performance-sensitive code may move to GDExtension only after profiling.

## Alternatives considered

C# remains possible only after an explicit architecture decision.

