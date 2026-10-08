# Leave Desk project instructions

## Purpose

- Build a responsive Ruby on Rails leave-management application.
- Treat `docs/product-brief.md` as the current source of product requirements.
- Treat undecided behavior as an open question, not an implicit requirement.

## Working process

- Inspect relevant requirements and code before changing behavior.
- Separate user requirements, assumptions, and technical decisions.
- For non-trivial changes, define acceptance criteria and verify them with tests.
- Update specifications and ADRs when behavior or architecture changes.
- Preserve leave history; prefer explicit state transitions to deletion.

## Domain rules

- A leave request belongs to one employee and one leave type.
- Its end date cannot precede its start date.
- New requests start pending.
- Only pending requests can be approved or rejected.
- Pending or approved requests can be cancelled.
- Approval and rejection record both the reviewer and review time.
- Self-approval is forbidden.
- Overlap and allowance accounting remain open until policy is specified.

## Safety

- Never expose credentials or production employee data in logs or examples.
- Do not add production dependencies without documenting their purpose.
- Prefer database constraints and transactions for business invariants.
- Do not run destructive database, Git, filesystem, or deployment operations
  without explicit approval.

## Verification

- `bin/rails db:prepare`
- `bin/rails test`
- `bin/rubocop`
- `bundle exec brakeman --no-pager`
