# Phase B Manual QA Checklist (AI Loaf Analysis)

- [ ] Pro user can open `Analyze Loaf` from Home.
- [ ] Non-pro user is routed to existing paywall when tapping `Analyze Loaf`.
- [ ] Camera photo capture works.
- [ ] Photo library selection via `PhotosPicker` works.
- [ ] Selected image preview appears before analysis.
- [ ] Validation rejects blurry images with friendly message.
- [ ] Validation rejects dark images with friendly message.
- [ ] Validation rejects images under 512 px with friendly message.
- [ ] Validation rejects unsupported image format.
- [ ] Validation rejects over-limit files.
- [ ] Upload starts and progress state is shown.
- [ ] Upload failure shows retry-friendly message.
- [ ] Analysis starts and progress state is shown.
- [ ] Malformed AI response returns friendly failure state.
- [ ] Network failure during analysis shows friendly failure state.
- [ ] Successful analysis shows scores, strengths, improvements, next steps, and summary.
- [ ] History reload shows persisted scans in descending date order.
- [ ] Signed URL image loading works for stored history images.
- [ ] Analytics events fire:
  - [ ] `photo_selected`
  - [ ] `upload_started`
  - [ ] `upload_completed`
  - [ ] `analysis_started`
  - [ ] `analysis_completed`
  - [ ] `analysis_failed` (on failure path)

