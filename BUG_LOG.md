# Bug Log

Central source of truth for product bugs and manual QA findings.

## Status Values

- Open
- In Progress
- Blocked
- Fixed
- Verified
- Won't Fix

## Priority Values

- P0
- P1
- P2
- P3

## Version History

| Date | Version | Changes |
| --- | --- | --- |
| 2026-07-25 | 1.0 / 1 | Initial bug log created. Added BUG-001. |

## Bug Summary

| Bug ID | Date Found | Area | Priority | Status | Title |
| --- | --- | --- | --- | --- | --- |
| BUG-001 | 2026-07-25 | Authentication — Sign Up | P1 | Open | Weak signup password shows incorrect generic error |

## Detailed Bugs

### BUG-001 — Weak signup password shows incorrect generic error

- **Date found:** 2026-07-25
- **Version / Build:** 1.0 / 1
- **Environment:** iPhone 17 Simulator, iOS 26.5
- **Area:** Authentication — Sign Up
- **Priority:** P1
- **Status:** Open

#### Description

Creating an account with a short password fails, but the app displays: "We could not sign you in. Please verify your credentials and try again."

The wording is incorrect because the user is signing up, and it does not explain the password requirement.

#### Steps to reproduce

1. Open the app.
2. Select Sign Up.
3. Enter a valid email.
4. Enter a password of approximately five characters.
5. Tap Create Account.

#### Actual result

- Signup fails.
- Generic sign-in error appears.
- No password requirement is shown.

#### Expected result

- Validate password before calling Supabase.
- Show: "Password must be at least 8 characters."
- Signup errors must use signup-specific wording.

#### Confirmed workaround

Use a stronger password with at least 8 characters.

#### Proposed solution

1. Add client-side minimum 8-character validation.
2. Disable Create Account or show inline guidance until valid.
3. Map safe Supabase errors:
   - weak password
   - invalid email
   - signup disabled
   - rate limit
   - network failure
4. On successful signup requiring verification, show: "Account created. Check your email to confirm your account."
5. Add focused tests.

#### Acceptance criteria

- Short passwords never reach Supabase.
- Clear password guidance is shown.
- Signup errors never use sign-in wording.
- Existing sign-in behavior remains unchanged.
- Tests and CI pass.

## New Bug Template

Copy this section and replace placeholders when adding a new bug.

```markdown
### BUG-XXX — <short title>

- **Date found:** YYYY-MM-DD
- **Version / Build:** <version / build>
- **Environment:** <device / OS / simulator>
- **Area:** <feature area>
- **Priority:** P0 | P1 | P2 | P3
- **Status:** Open | In Progress | Blocked | Fixed | Verified | Won't Fix

#### Description

<clear description of the issue>

#### Steps to reproduce

1. <step 1>
2. <step 2>
3. <step 3>

#### Actual result

- <actual outcome>

#### Expected result

- <expected outcome>

#### Confirmed workaround

<workaround or "None">

#### Proposed solution

1. <proposal item>
2. <proposal item>

#### Acceptance criteria

- <criterion 1>
- <criterion 2>
```
