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
| 2026-07-27 | 1.0 / 1 | Verified BUG-005 in simulator and remote Supabase (starter + feeding ownership, single active starter). |
| 2026-07-26 | 1.0 / 1 | Added BUG-005 (fixed) for missing `user_id` in starter/feeding inserts and BUG-006 (open) for developer-scaffold Home screen. |
| 2026-07-26 | 1.0 / 1 | Added and fixed BUG-004 email confirmation callback redirect. |
| 2026-07-26 | 1.0 / 1 | Added BUG-003 navigation back/close visibility issue. |
| 2026-07-26 | 1.0 / 1 | Added BUG-002 paywall offerings failure trap issue. |
| 2026-07-25 | 1.0 / 1 | Initial bug log created. Added BUG-001. |

## Bug Summary

| Bug ID | Date Found | Area | Priority | Status | Title |
| --- | --- | --- | --- | --- | --- |
| BUG-006 | 2026-07-26 | Home | P1 | Open | Home screen is internal developer scaffold |
| BUG-005 | 2026-07-26 | Starter Workflow — Persistence | P0 | Verified | Starter and feeding inserts omit required user_id |
| BUG-004 | 2026-07-26 | Authentication — Email Confirmation | P1 | Fixed | Email confirmation redirects to unavailable localhost URL |
| BUG-003 | 2026-07-26 | Navigation | P1 | Open | Multiple app screens lack visible back navigation |
| BUG-002 | 2026-07-25 | Monetization — Paywall | P1 | Open | Paywall traps user when subscriptions are unavailable |
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

### BUG-002 — Paywall traps user when subscriptions are unavailable

- **Date found:** 2026-07-25
- **Version / Build:** 1.0 / 1
- **Environment:** iPhone 17 Simulator, iOS 26.5
- **Area:** Monetization — Paywall
- **Priority:** P1
- **Status:** Open

#### Description

When RevenueCat offerings fail to load, the paywall shows "Subscriptions unavailable" but provides no visible back or close button. The user becomes trapped on the paywall.

#### Steps to reproduce

1. Launch the app.
2. Open the paywall.
3. Encounter an offerings-load failure.
4. Observe the failure screen.

#### Actual result

- No visible close or back button.
- No retry button.
- User cannot clearly return to the app.

#### Expected result

- Visible close button in all paywall states.
- Retry button in failure state.
- Swipe-to-dismiss preserved.
- Pro gating remains enforced.

#### Confirmed workaround

Swipe down on the sheet or relaunch the app.

#### Proposed solution

1. Add `@Environment(\.dismiss)` to `PaywallView`.
2. Add a top-right `xmark` button.
3. Add accessibility label "Close paywall".
4. Add Retry button calling `loadOfferings()`.
5. Preserve purchase, restore, and entitlement behavior.
6. Add focused tests.

#### Acceptance criteria

- Paywall always has a visible dismiss control.
- Retry works after offerings failure.
- Non-Pro users cannot bypass gating.
- Existing purchase/restore flow still works.
- Tests and CI pass.

### BUG-003 — Multiple app screens lack visible back navigation

- **Date found:** 2026-07-26
- **Version / Build:** 1.0 / 1
- **Environment:** iPhone 17 Simulator, iOS 26.5
- **Area:** Navigation
- **Priority:** P1
- **Status:** Open

#### Description

Multiple non-root screens do not show a visible Back or Close control, making navigation confusing or trapping the user.

#### Actual result

- Users cannot clearly return to the previous screen.
- Navigation behavior is inconsistent across the app.
- Some modal screens also lack a Close button.

#### Expected result

- Pushed screens use the native iOS Back button.
- Modal sheets have a visible Close button.
- Root screens do not show an unnecessary Back button.
- Swipe-back and swipe-to-dismiss remain available.

#### Proposed solution

1. Audit every Phase A and Phase B screen.
2. Ensure one shared `NavigationStack` owns pushed navigation.
3. Remove nested `NavigationStack`s that suppress native back controls.
4. Use `navigationDestination` or `NavigationLink` for pushed screens.
5. Add toolbar Close buttons to modal sheets.
6. Do not add custom back buttons where native navigation works.
7. Add accessibility labels and navigation tests.

#### Acceptance criteria

- Every non-root screen has an obvious return path.
- No screen traps the user.
- Native swipe navigation works.
- Paywall handling remains tracked separately as `BUG-002`.
- Tests and CI pass.

### BUG-004 — Email confirmation redirects to unavailable localhost URL

- **Date found:** 2026-07-26
- **Version / Build:** 1.0 / 1
- **Environment:** iPhone 17 Simulator, iOS 26.5
- **Area:** Authentication — Email Confirmation
- **Priority:** P1
- **Status:** Verified

#### Description

Supabase confirmation email redirected to `http://localhost:3000/?code=...`, which is unavailable on device/simulator and prevented app callback handling.

#### Root cause

- Signup requests did not provide an app redirect URL.
- The app did not register or handle an auth callback URL scheme at the root.

#### Fix implemented

1. Registered app URL scheme `bakingapp://auth-callback`.
2. Passed exact redirect URL during signup through Supabase Auth SDK.
3. Handled incoming callback URLs at app root and exchanged callback for session via SDK.
4. Refreshed session state and routed into authenticated flow after successful callback.
5. Added safe invalid/expired callback error messaging without exposing URL/code/token details.
6. Added focused tests for redirect URL, callback validation, rejection behavior, and callback session refresh.

#### Acceptance criteria

- Confirmation emails redirect to app callback URL.
- Successful callbacks sign the user in through normal app routing.
- Invalid/expired callbacks show safe user-facing errors.
- Sensitive callback/auth data is not logged.

### BUG-005 — Starter and feeding inserts omit required user_id

- **Date found:** 2026-07-26
- **Version / Build:** 1.0 / 1
- **Environment:** iPhone 17 Simulator, iOS 26.5
- **Area:** Starter Workflow — Persistence
- **Priority:** P0
- **Status:** Fixed

#### Description

Creating starter profiles and feeding logs failed against production because insert payloads omitted the required `user_id` column (`NOT NULL` + RLS owner checks).

#### Root cause

- `StarterInsert` payload omitted `user_id`.
- `FeedingLogInsert` payload omitted `user_id`.
- Active-starter creation flow deactivated existing active records before new creation completed.

#### Fix implemented

1. Added authenticated `user_id` to starter insert payload.
2. Added authenticated `user_id` to feeding-log insert payload.
3. Changed active-starter creation flow to insert first, then deactivate other starters.
4. Added repository error mapping for safe actionable messages and DEBUG-only technical logging.
5. Added repository tests and scripted real Supabase integration checks for owner insert and cross-user rejection.

#### Acceptance criteria

- Starter and feeding inserts include authenticated user ownership fields.
- Failed active starter creation does not deactivate previous active starter.
- RLS allows owner inserts and rejects cross-user inserts.
- User-facing errors are safe and actionable.

#### Verification evidence (2026-07-27)

- **Environment:** iPhone 17 Simulator, iOS 26.5
- **Manual app flow:** Signed in, created starter `BUG005 Verification` as active, opened starter details, created feeding log, and confirmed feeding history entry.
- **Remote Supabase checks (linked project):** Starter row exists; starter row has owning user; feeding row exists for the same user/starter; exactly one active starter exists for that user.

### BUG-006 — Home screen is internal developer scaffold

- **Date found:** 2026-07-26
- **Version / Build:** 1.0 / 1
- **Environment:** iPhone 17 Simulator, iOS 26.5
- **Area:** Home
- **Priority:** P1
- **Status:** Open

#### Description

Current Home screen is a developer scaffold and does not represent final product navigation/content expectations.

#### Scope note

This issue is tracked only in the bug log for now. No implementation changes are included in this fix.

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
