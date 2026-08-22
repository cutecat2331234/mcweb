# Role management production contract

## Ownership decision

Role administration is a shared identity and authorization capability, so CE
owns the workflow. EE and EE-PVP consume the same pages and service behavior
through ordinary downstream merges; neither edition may recreate it.

## Task checklist

- [x] Replace the read-only generic role screens with dedicated Arco pages.
- [x] Expose create and edit forms only to administrators with both role read
      and manage permissions.
- [x] Group the assignable permission catalog without exposing permissions the
      acting administrator cannot delegate.
- [x] Show assignment counts and immutable-system-role state before mutation.
- [x] Require a replacement role before retiring a role that has members.
- [x] Move assignments atomically, deduplicate existing replacement
      assignments, and audit counts without personal data.
- [x] Reject stale, self-replacement, forbidden replacement, and system-role
      retirement requests.
- [x] Add controller, service, rendering, localization, and contract coverage.
- [ ] Merge the CE history through EE into EE-PVP.

## Functional requirements

### Role list and editor

1. The list reports role name, stable key, permission count, member count, and
   system/custom status with paging.
2. Creating and editing use the existing Arco form, input, checkbox, alert,
   button, modal, and result components; no page-local visual language is
   introduced.
3. System roles remain readable but cannot be edited or retired.
4. Permission choices are grouped by catalog area and translated. A non-owner
   may only add permissions they currently hold and that the catalog marks as
   assignable.
5. Validation and authorization failures return localized feedback and retain
   an intact database state.

### Safe retirement

1. An unused custom role may be retired after explicit confirmation.
2. A custom role with members requires a different, manageable replacement
   role; a plain destructive request is rejected.
3. The role row, its permission links, and every user assignment are locked in
   one transaction before the move.
4. Users already carrying the replacement role are not given duplicate links.
5. The audit records the retired role snapshot, replacement role identifier,
   and assignment counts, never user email addresses or names.
6. Failed or concurrent requests leave the source role and all assignments
   recoverable and consistent.

## Acceptance checklist

- A reader sees dedicated role pages but no mutation controls.
- A manager can create a custom role with allowed permissions and edit it.
- A system role shows a clear immutable state and offers no mutation action.
- Retiring an assigned role without a replacement fails without data loss.
- Retiring with a valid replacement preserves each affected user's access row
  and produces one bounded audit record.
- All visible text belongs to the shared McWeb locale bundle in Chinese and
  English.
