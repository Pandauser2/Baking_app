# Phase B Starter Workflow QA Checklist

- [ ] Sign in with a Pro user.
- [ ] Create starter profile with name and optional hydration.
- [ ] Verify one active starter is shown on Home flow.
- [ ] Add feeding log with valid room temp and optional ingredients.
- [ ] Verify invalid temp and negative grams show friendly validation.
- [ ] Open scan flow, pick photo from library, pass quality gate.
- [ ] Capture photo with camera and verify quality gate feedback.
- [ ] Verify upload path uses `<user>/<starter>/<year>/<month>/<uuid>.jpg`.
- [ ] Verify analyze call returns structured starter JSON.
- [ ] Verify Save persists scan, analysis, recommendation, starter state.
- [ ] Mark recommendation outcome and verify status updates.
- [ ] Re-scan within 7 days and verify context-aware comparison appears.
- [ ] Verify non-Pro user is redirected to paywall when analyzing.
- [ ] Confirm loaf feature is hidden on Home and still compiles.
