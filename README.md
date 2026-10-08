# Leave Desk

Leave Desk is an independent Rails/PostgreSQL application for managing
employee leave requests and approval workflows.

The first vertical slice models employees, leave types, and the request
approval lifecycle. See `docs/product-brief.md` and
`docs/specifications/001-leave-request-lifecycle.md` before extending it.

## Requirements

- Ruby 4.0
- Rails 8.1
- PostgreSQL 16+

## Setup

```sh
bundle install
bin/rails db:prepare
bin/rails test
```

## Product boundaries

The MVP covers employee leave requests and manager approval. Overtime, payroll integration, advanced accrual policies, SSO, and multi-tenant hosting are explicitly deferred until their rules are specified.
