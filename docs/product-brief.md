# Product brief: Leave Desk

## Goal

Provide a small organization with a clear workflow for requesting, reviewing, and tracking employee leave.

## MVP users

- **Employee** submits and tracks their own leave requests.
- **Manager** reviews requests from employees they manage.
- **Administrator** manages employees and leave types.

## MVP capabilities

- Maintain employees and their reporting manager.
- Configure active leave types.
- Submit a dated leave request with an optional employee comment.
- Approve or reject a pending request and retain the review audit data.
- Cancel a pending or approved request without deleting its history.
- Show personal and team request lists.

## Core invariants

- Dates are inclusive and the end date is not before the start date.
- A request begins in `pending` status.
- A final review identifies its reviewer and timestamp.
- An employee cannot review their own request.
- Historical requests are retained.

## Open questions

- Whether weekends and public holidays consume allowance.
- Whether overlapping requests are forbidden or only warned about.
- Accrual, carry-over, negative balances, and part-day leave.
- Delegated approvers and multi-level approval.
- Organization structure deeper than the direct manager relationship.
- Notification channels and reminder timing.

## Out of scope for the first slice

- Overtime and compensatory time.
- Payroll or HRIS integrations.
- SSO/LDAP/SAML.
- Calendar feeds and public APIs.
- Multi-tenancy and localization.
