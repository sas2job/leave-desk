# Specification 001: leave request lifecycle

## Acceptance criteria

1. A valid request has an employee, an active leave type, a start date, and an end date on or after the start date.
2. A newly persisted request is pending.
3. A pending request can be approved by another user; reviewer and review time are recorded atomically.
4. A pending request can be rejected with the same audit data.
5. A pending or approved request can be cancelled.
6. Approved, rejected, and cancelled requests cannot be reviewed again.
7. Failed transitions do not partially change the request.

## Deferred policy

This specification does not calculate leave duration or enforce allowance and overlap rules. Those require explicit policies for calendars, part days, and
regional holidays.
