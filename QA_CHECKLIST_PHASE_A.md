# Phase A Manual QA Checklist

## Setup
- [ ] Add `BakingApp/Resources/Config/Config.local.xcconfig` from `.example`.
- [ ] Add `BakingApp/Resources/Config/GoogleService-Info.plist` from `.example`.
- [ ] In Xcode scheme, attach `BakingApp/Resources/BakingApp.storekit` for local StoreKit testing.
- [ ] Configure RevenueCat with products:
  - [ ] `com.pandauser2.bakingapp.pro.monthly`
  - [ ] `com.pandauser2.bakingapp.pro.yearly`
  - [ ] entitlement: `pro`

## Auth Flow
- [ ] Clean install launches app.
- [ ] Sign-up succeeds with email/password.
- [ ] Sign-in succeeds with email/password.
- [ ] Session restores after app relaunch.
- [ ] Sign-out returns to authentication screen.

## Onboarding
- [ ] Onboarding appears once after first successful authentication.
- [ ] Onboarding does not reappear after completion and relaunch.

## Paywall and Billing
- [ ] Home placeholder renders app name, user state, entitlement state.
- [ ] Paywall is accessible from Home.
- [ ] Monthly sandbox purchase succeeds.
- [ ] Yearly sandbox purchase succeeds.
- [ ] Purchase cancellation shows cancellation feedback.
- [ ] Restore purchases succeeds after reinstall/sign-in.
- [ ] Expired entitlement state is reflected after refresh.
- [ ] Offerings unavailable shows user-friendly error.

## Configuration and Error Handling
- [ ] Missing configuration file fails clearly in Debug.
- [ ] Auth failures show user-friendly errors.
- [ ] Session restoration failure shows user-friendly error.
- [ ] Restore failure shows user-friendly error.

## Analytics + Crash Reporting
- [ ] `signup_completed` emitted on successful sign-up.
- [ ] `login_completed` emitted on successful sign-in.
- [ ] `onboarding_completed` emitted on onboarding finish.
- [ ] `paywall_viewed` emitted when paywall opens.
- [ ] `purchase_completed` emitted on successful purchase.
- [ ] `purchase_restored` emitted on restore success.
- [ ] Crashlytics test crash is visible in Firebase console (Release/TestFlight build).

