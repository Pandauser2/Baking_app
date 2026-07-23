# Baking App (Phase A Foundation)

This repository contains Phase A of the iOS Sourdough Coach roadmap:
- SwiftUI app shell and launch routing
- Supabase email auth
- Onboarding flow
- RevenueCat paywall infrastructure
- Firebase Analytics and Crashlytics wiring
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
4. Copy `BakingApp/Resources/Config/GoogleService-Info.plist.example` to:
   - `BakingApp/Resources/Config/GoogleService-Info.plist`
5. In Xcode, open `BakingApp.xcodeproj`.
6. Use scheme `BakingApp` with `BakingApp/Resources/BakingApp.storekit` for local StoreKit sandbox testing.

## Notes

- Never commit `Config.local.xcconfig` or `GoogleService-Info.plist`.
- No server-side keys are used in the app.
- Supabase migration is in `supabase/migrations/0001_phase_a_users.sql`.

