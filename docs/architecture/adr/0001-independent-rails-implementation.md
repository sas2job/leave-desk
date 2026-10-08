# ADR 0001: independent Rails implementation

## Status

Accepted

## Context

Leave Desk needs a maintainable foundation for leave-management workflows and
a specification-first development process.

## Decision

Build Leave Desk as an independent Rails/PostgreSQL application with its own
domain model, interface, and delivery roadmap.

## Consequences

- The domain can use Rails conventions and PostgreSQL constraints directly.
- Each feature requires local acceptance criteria.
- Integrations and data migrations require separate specifications.
