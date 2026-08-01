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
| 2026-08-01 | 1.0 / 1 | Verified BUG-003 after product-owner manual QA on commit `9963081` (chevron visible, Timeline→Details back passed, CI green). |
| 2026-08-01 | 1.0 / 1 | BUG-003 visual polish: chevron-only Back toolbar control (no clipped `Back` text). Navigation behavior manually passed; status remains Fixed pending PO screenshot verification. |
| 2026-08-01 | 1.0 / 1 | Fully resolved BUG-003 with single HomeNavigationRouter, explicit Back control, real QA coordinate-tap proof (Fixed, not Verified). |
| 2026-07-31 | 1.0 / 1 | Fixed BUG-003 visible-but-nonfunctional back navigation via single path-based Home NavigationStack (Fixed, not Verified). |
| 2026-07-31 | 1.0 / 1 | Verified BUG-010 with manual persistence/outcome evidence; added and fixed BUG-011 previous-scan comparison (Fixed after real linked-Supabase E2E). |
| 2026-07-31 | 1.0 / 1 | Fully resolved BUG-010 end-to-end: nested timeline decode + post-save refresh + idempotent persist RPC (Fixed after real linked-Supabase E2E). |
| 2026-07-31 | 1.0 / 1 | Reopened BUG-010 after post-fix manual run still failed to transition to saved state (status set back to Open). |
| 2026-07-31 | 1.0 / 1 | Added BUG-010 and fixed starter-analysis save diagnostics + duplicate-save guard (Fixed, not Verified). |
| 2026-07-31 | 1.0 / 1 | Added BUG-009 and fixed non-starter subject handling with explicit invalid-subject contract (Fixed, not Verified). |
| 2026-07-30 | 1.0 / 1 | Added BUG-008 and implemented safe structured starter-analysis diagnostics with fixed error mapping (Fixed, not Verified). |
| 2026-07-30 | 1.0 / 1 | Added and fixed BUG-007 stale starter-list active-state consistency issue after active starter creation (Fixed, not Verified). |
| 2026-07-27 | 1.0 / 1 | Finalized BUG-005 verification evidence: nil hydration RPC serialization fix, regression coverage, and green CI. |
| 2026-07-27 | 1.0 / 1 | Verified BUG-005 in simulator and remote Supabase (starter + feeding ownership, single active starter). |
| 2026-07-26 | 1.0 / 1 | Added BUG-005 (fixed) for missing `user_id` in starter/feeding inserts and BUG-006 (open) for developer-scaffold Home screen. |
| 2026-07-26 | 1.0 / 1 | Added and fixed BUG-004 email confirmation callback redirect. |
| 2026-07-26 | 1.0 / 1 | Added BUG-003 navigation back/close visibility issue. |
| 2026-07-26 | 1.0 / 1 | Added BUG-002 paywall offerings failure trap issue. |
| 2026-07-25 | 1.0 / 1 | Initial bug log created. Added BUG-001. |

## Bug Summary

| Bug ID | Date Found | Area | Priority | Status | Title |
| --- | --- | --- | --- | --- | --- |
| BUG-011 | 2026-07-31 | Starter Workflow — Comparison | P1 | Fixed | Previous starter scan is ignored during comparison |
| BUG-010 | 2026-07-31 | Starter Workflow — Persistence | P0 | Verified | Saving starter analysis fails |
| BUG-009 | 2026-07-31 | Starter Workflow — Analysis Subject Validation | P1 | Fixed | Explicitly reject non-starter images |
| BUG-008 | 2026-07-30 | Starter Workflow — Analysis | P0 | Fixed | Starter analysis fails in QA build |
| BUG-007 | 2026-07-30 | Starter Workflow — UI Consistency | P1 | Fixed | Starter list temporarily shows multiple active starters |
| BUG-006 | 2026-07-26 | Home | P1 | Open | Home screen is internal developer scaffold |
| BUG-005 | 2026-07-26 | Starter Workflow — Persistence | P0 | Verified | Starter and feeding inserts omit required user_id |
| BUG-004 | 2026-07-26 | Authentication — Email Confirmation | P1 | Fixed | Email confirmation redirects to unavailable localhost URL |
| BUG-003 | 2026-07-26 | Navigation | P1 | Verified | Back navigation is visible but nonfunctional |
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

### BUG-003 — Back navigation is visible but nonfunctional

- **Date found:** 2026-07-26
- **Version / Build:** 1.0 / 1
- **Environment:** BakingApp-QA, iPhone 17 Simulator, iOS 26.5
- **Area:** Navigation
- **Priority:** P1 (Phase B release blocker)
- **Status:** Verified

#### Description

Back navigation can appear in the navigation bar but does not pop the stack. Exact Phase B reproduction: Home → Open starter details → Timeline → tap visible back button → nothing happens. Expected: Timeline pops back to Starter Details immediately.

Commit `f029b09` claimed a path-based fix and green UI tests, but BakingApp-QA still failed the exact Timeline back tap (native chevron coordinate tap left Timeline visible; evidence in `Tests/Fixtures/bug003_pre_fix/`).

#### Root cause

1. `RootView` recreated `HomeView(viewModel: StarterWorkflowViewModel(...))` on every auth/billing refresh, destabilizing navigation ownership.
2. Opaque `NavigationPath` + native UIKit back chevron desynced on iOS 26 — visible back received taps but did not pop.
3. Prior UITests used accessibility `BackButton` activate, not the large visible coordinate hit target humans tap (false confidence).

#### Fix implemented

1. Single stable `HomeNavigationRouter` + one Home `NavigationStack(path:)` owned from `RootView` (`HomeViewModelHolder` prevents ViewModel churn).
2. All pushes/pops go through router; duplicate top pushes ignored.
3. Native system back hidden; one explicit toolbar Back control (≥44×44, accessibility label `Back`, per-screen accessibility id) calling `router.pop()`.
4. Edge-swipe also calls the same `router.pop()` (no competing owners).
5. DEBUG navigation logs: screen/route/pathCount/backTap/resultingPathCount.
6. Pre-fix + three-run post-fix screenshot fixtures; full Debug and BakingApp-QA UI tests.
7. Visual polish: chevron-only toolbar control (`chevron.left`) so the label is never clipped as `B…` / `Bac`.

#### Manual verification evidence (2026-08-01)

- **Build/commit:** `996308175e4857725e39c0689b581326cd0472ad`
- Timeline → Starter Details back navigation passed
- Chevron was fully visible
- No clipped `Back` text appeared
- CI green: https://github.com/Pandauser2/Baking_app/actions/runs/30700232305

#### Acceptance criteria

- Timeline → Starter Details back works by button tap (coordinate proof).
- Edge-swipe back works via the same router pop.
- Starter Details → Home, Feeding History, Log Feeding, Scan Starter, Analysis Result, and Starter List back paths work.
- No blank screen, lost navigation state, or duplicate routes.
- Single Home navigation owner; no competing back mechanisms.
- Timeline/recommendation data remain intact after navigating back/forward.
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
- **Status:** Verified

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
6. Fixed RPC payload serialization so `p_hydration_preference` is sent as explicit JSON `null` when hydration is empty (instead of omitting the key).
7. Added focused regression tests for `CreateStarterProfilePayload` encoding:
   - nil hydration includes `p_hydration_preference`
   - nil hydration serializes as JSON null
   - non-nil hydration serializes as numeric value
   - `user_id` / `p_user_id` cannot be injected

#### Acceptance criteria

- Starter and feeding inserts include authenticated user ownership fields.
- Failed active starter creation does not deactivate previous active starter.
- RLS allows owner inserts and rejects cross-user inserts.
- User-facing errors are safe and actionable.

#### Verification evidence (2026-07-27)

- **Environment:** iPhone 17 Simulator, iOS 26.5
- **Manual app flow:** Signed in, created starter `BUG005 Verification` as active, opened starter details, created feeding log, and confirmed feeding history entry.
- **Remote Supabase checks (linked project):** Starter row exists; starter row has owning user; feeding row exists for the same user/starter; exactly one active starter exists for that user.
- **Regression coverage:** Focused payload-encoding tests pass for nil/non-nil hydration and anti-injection checks.
- **CI:** GitHub Actions `iOS CI` passed for `Fix optional hydration RPC serialization` ([run 30297289335](https://github.com/Pandauser2/Baking_app/actions/runs/30297289335)).

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

### BUG-007 — Starter list temporarily shows multiple active starters

- **Date found:** 2026-07-30
- **Version / Build:** 1.0 / 1
- **Environment:** iPhone 17 Simulator, iOS 26.5
- **Area:** Starter Workflow — UI Consistency
- **Priority:** P1
- **Status:** Fixed

#### Description

Immediately after creating a new starter as active, the local list briefly showed both the previous starter and the newly created starter as `Active`.

#### Root cause

- `StarterWorkflowViewModel.createStarter` inserted the returned starter into the cached list.
- The previous cached starter `active` flag was not reconciled locally before the next canonical reload.
- The UI could briefly render stale local state until another refresh path corrected it.

#### Fix implemented

1. On successful active starter creation, the view model now immediately reconciles cached local state by marking all existing starters inactive and inserting the created active starter without duplicates.
2. The view model then reloads starters from the repository as the authoritative backend state.
3. If that refresh fails, the reconciled local state is retained and a safe nonblocking refresh message is shown.
4. Home and Starter List now share the same `StarterWorkflowViewModel` instance and trigger refresh on return from Starter List.

#### Acceptance criteria

- Active starter creation never leaves more than one local `Active` badge during transient refresh windows.
- Inactive starter creation preserves existing active starter.
- Refresh failures do not convert successful creation into a user-visible creation failure.
- No duplicate starter rows appear in local list state.
- Focused tests and CI pass.

### BUG-008 — Starter analysis fails in QA build

- **Date found:** 2026-07-30
- **Version / Build:** 1.0 / 1
- **Environment:** iPhone 17 Simulator, iOS 26.5, `BakingApp-QA`
- **Area:** Starter Workflow — Analysis
- **Priority:** P0
- **Status:** Open

#### Description

Starter scan upload succeeds, but analysis can fail with a generic error message: "Analysis failed. Please try again." The client discarded non-2xx function response bodies, which hid actionable failure details.

#### Root cause

- The `analyze-starter` Edge Function returned unstructured errors (`error`) and collapsed provider failures into generic values (for example, `provider_400`).
- The iOS repository did not decode non-2xx error bodies from `analyze-starter` and always surfaced generic analysis failure text.
- This masked the exact failing layer (provider auth/quota/rate-limit/timeout/schema/image issues) during QA.

#### Fix implemented

1. Added structured safe error responses in `analyze-starter` with:
   - `error_code`
   - safe `message`
   - `request_id` correlation ID
2. Added explicit error-code mapping for:
   - `AUTH_INVALID`
   - `STARTER_NOT_FOUND`
   - `IMAGE_DOWNLOAD_FAILED`
   - `IMAGE_INVALID`
   - `PROVIDER_AUTH`
   - `PROVIDER_QUOTA`
   - `PROVIDER_RATE_LIMIT`
   - `PROVIDER_TIMEOUT`
   - `PROVIDER_RESPONSE_INVALID`
   - `INTERNAL_ERROR`
3. Updated iOS analysis networking to decode non-2xx function bodies and map structured error codes to safe actionable user messages.
4. Added DEBUG-only safe diagnostics logging for analysis failures:
   - `request_id`
   - HTTP status
   - `error_code`
5. Added focused tests for structured error mapping and provider/schema timeout behavior.

#### Acceptance criteria

- Non-2xx `analyze-starter` responses include structured safe fields and request correlation.
- iOS no longer discards safe non-2xx payloads and shows actionable errors.
- DEBUG diagnostics include only correlation ID, status, and error code.
- No auth/RLS/storage ownership weakening introduced.

### BUG-009 — Explicitly reject non-starter images

- **Date found:** 2026-07-31
- **Version / Build:** 1.0 / 1
- **Environment:** iPhone 17 Simulator, iOS 26.5, `BakingApp-QA`
- **Area:** Starter Workflow — Analysis Subject Validation
- **Priority:** P1
- **Status:** Fixed

#### Description

Non-starter photos (for example, waterfall images) could pass client-side quality checks and reach AI analysis, but the backend contract only allowed starter-analysis schema. This produced provider validation errors instead of a product-safe subject rejection.

#### Root cause

- The analysis contract only supported one shape (starter analysis).
- There was no schema-valid result for "not a sourdough starter" or "uncertain subject."
- The system treated non-starter cases as provider/schema failures rather than valid product outcomes.

#### Fix implemented

1. Added discriminated result contract support:
   - `starter_analysis`
   - `invalid_subject` (`not_starter` or `uncertain`)
2. Edge Function now validates both variants strictly and returns `invalid_subject` as HTTP 200.
3. Added safe rejection messages for non-starter and uncertain subject outcomes.
4. iOS parser and workflow now decode `invalid_subject`, display the safe message, and block persistence.
5. Persistence path remains unchanged for valid `starter_analysis`.
6. Added focused Deno and iOS tests for both variants, malformed provider output, and no-persist rejection behavior.

#### Acceptance criteria

- Non-starter/uncertain images return valid `invalid_subject` outcomes.
- Rejections do not persist scans, analyses, recommendations, or starter-state updates.
- Valid starter analysis flow still persists normally.
- Provider/network/schema failures continue using structured error codes.

### BUG-010 — Saving starter analysis fails

- **Date found:** 2026-07-31
- **Version / Build:** 1.0 / 1
- **Environment:** iPhone 17 Simulator, iOS 26.5, `BakingApp-QA`
- **Area:** Starter Workflow — Persistence
- **Priority:** P0
- **Status:** Verified

#### Description

After successful starter analysis, tapping `Save Analysis` could leave the app in a broken saved state: Save button disappeared, recommendation card did not appear, and UI showed "We received an unexpected response from the server. Please try again."

#### Root cause

- Persistence RPC could commit successfully, then post-save refresh failed.
- Timeline nested query returns one-to-one `ai_analyses` as a JSON object; iOS decoded only `[StarterAnalysis]` arrays.
- That `DecodingError` was mapped to "unexpected response from the server" after `persistedIDs` was set, so Save disappeared without a recommendation.
- Earlier layers (nullable RPC args, missing path uniqueness) also contributed and remain hardened.

#### Fix implemented

1. Flexible PostgREST relation decoding for nested `ai_analyses` / `recommendations` (object or array).
2. Fractional ISO-8601 date decoding for Postgres timestamps.
3. Post-save refresh uses returned recommendation ID first; timeline refresh is secondary and cannot make a successful save appear failed.
4. Clear stale errors before/after successful save; non-destructive refresh guidance only if recommendation refresh fails.
5. Idempotent `persist_starter_analysis` by storage path plus unique index `scans_starter_user_path_unique`.
6. Real-backend fixtures and E2E script proving RPC, row counts, restart reload, and decoder compatibility.

#### Manual verification evidence (2026-07-31)

- Save succeeded
- Recommendation appeared
- Outcome changed to Followed
- App restarted
- Timeline reloaded
- Followed outcome persisted

#### Acceptance criteria

- Successful DB commit transitions UI to saved state with recommendation card.
- Timeline decode failures after save do not present as save failures.
- Duplicate save retries return the same IDs and create exactly one scan/analysis/recommendation per storage path.
- Real linked-Supabase E2E passes with restart/reload proof.

### BUG-011 — Previous starter scan is ignored during comparison

- **Date found:** 2026-07-31
- **Version / Build:** 1.0 / 1
- **Environment:** iPhone 17 Simulator / linked Supabase `msyrqznbrndkjlwwhqeg`
- **Area:** Starter Workflow — Comparison
- **Priority:** P1 (Phase B release blocker)
- **Status:** Fixed

#### Description

A later starter analysis showed “No previous data to compare.” even when an earlier saved scan existed for the same starter (e.g. prior scan 31 Jul 2026 5:31 PM, later analysis 6:14 PM).

#### Root cause

- `analyze-starter` dumped raw recent scans/analyses into the prompt without an explicit `previous_analysis` pointer.
- Prompt wording asked for what “visibly changed” while only the current image was provided (no previous image).
- There was no server-side validation preventing “no previous data” when valid prior completed analysis context existed.
- This was not solely a model failure: the contract invited visual comparison without previous-image input.

#### Fix implemented

1. `loadHistoryContext` now builds sanitized context with `has_previous_analysis` + `previous_analysis` from the latest prior completed analyzed scan (excluding current image path; skipping missing nested analyses).
2. Prompt v2 compares against prior recorded analysis/state text; forbids fabricating pixel-level visual differences without prior-image input.
3. Deterministic `enforceComparisonConsistency` rejects/repairs “no previous data” when prior context exists, and forces the canonical no-previous message when none exists.
4. Linked-Supabase E2E (`scripts/e2e/bug011_comparison_e2e.py`) saves A then B, proves B receives A context and meaningful comparison, and confirms both remain in timeline.
5. Fixtures/tests cover zero/one/multiple priors, invalid-subject history, missing nested analysis, and Followed prior outcome.

#### Acceptance criteria

- No previous saved analysis → “No previous data to compare.”
- Previous saved analysis exists → comparison references it.
- Current in-progress image does not count as previous.
- Multiple scans use latest prior completed scan.
- Invalid-subject history does not participate.
- Missing nested analysis skips to older completed scan without crash.
- Comparison does not fabricate unsupported visual differences when only textual history is available.

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
