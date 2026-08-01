# Baking App (Phase A + Phase B Core)

This repository contains:
- SwiftUI app shell and launch routing
- Supabase email auth
- Onboarding flow
- RevenueCat paywall infrastructure
- Firebase Analytics and Crashlytics wiring
- Phase B loaf analysis flow (capture/select -> upload -> edge analysis -> result/history)
- Focused unit tests

## Setup

1. Install Xcode (full app, not Command Line Tools only).
2. Copy `BakingApp/Resources/Config/Config.local.xcconfig.example` to:
   - `BakingApp/Resources/Config/Config.local.xcconfig`
3. Fill values in `Config.local.xcconfig`:
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`
   - `REVENUECAT_PUBLIC_KEY`
   - `REVENUECAT_ENTITLEMENT_ID` (default: `pro`)
   - `APPLE_DEVELOPMENT_TEAM` (10-character Apple Team ID; required for Archive / TestFlight)
4. Copy `BakingApp/Resources/Config/GoogleService-Info.plist.example` to:
   - `BakingApp/Resources/Config/GoogleService-Info.plist`
5. In Xcode, open `BakingApp.xcodeproj`.
6. Use scheme `BakingApp` with `BakingApp/Resources/BakingApp.storekit` for local StoreKit sandbox testing.

## Notes

- Never commit `Config.local.xcconfig` or `GoogleService-Info.plist`.
- No server-side keys are used in the app.
- Supabase migrations are in:
  - `supabase/migrations/0001_phase_a_users.sql`
  - `supabase/migrations/0002_phase_b_loaf_scans.sql`
- Deploy edge function:
  - `supabase/functions/analyze-loaf/index.ts`

