# Phase C Execution Plan

Branch: `feature/phase-c`  
Base release-candidate: `3ef4df73467d07af536d090df7e19a46de32020f`  
Status: Phase C1 Bake Journal foundation in progress on `feature/phase-c`.

## Objective

Extend the product loop from starter coaching to bake outcomes:

- Bake journal entries
- Loaf scans
- AI loaf analysis
- Previous-bake comparison

Acceptance: user can record a bake, scan a loaf, and see what improved/regressed vs previous.

**Design principle:** Progressive disclosure. Show core fields first; optional fields under “More details.”  
**Product advantage:** Fewer fields plus AI comparison — not a Loaflo-style long expert form.

## Approved MVP bake fields (2026-08-04)

### Required

| Field | DB column |
| --- | --- |
| Bake date | `baked_at` |
| Name | `name` |
| Dough hydration | `dough_hydration_percent` |
| Bulk fermentation duration | `bulk_fermentation_minutes` |
| Final proof duration | `final_proof_minutes` |
| Mixing method | `mixing_method` |
| Shaping method | `shaping_method` |
| Oven temperature | `oven_temperature_c` |
| Baking time | `baking_time_minutes` |
| Result rating (1–5) | `result_rating_1_to_5` |

### Optional

| Field | DB column |
| --- | --- |
| Fermentation temperature (normalized °C) | `fermentation_temperature_c` |
| Fermentation temperature source | `fermentation_temperature_source` (`room` \| `dough`) |
| Retardation duration | `retardation_minutes` |
| Number of folds | `number_of_folds` |
| Steaming method | `steaming_method` |
| Flour notes | `flour_notes` |
| Notes | `notes` |

### Deferred (not in Phase C MVP schema)

- pH
- Starter / flour / water ratio fields
- Second oven temperature
- Loaf weight
- Separate goals / ingredients module
- 10-point rating

### Fermentation temperature (still approved; optional)

| Decision | Value |
| --- | --- |
| Field label | Fermentation temperature |
| Required | Optional |
| Input units | Celsius and Fahrenheit (UI conversion) |
| Source enum | `room` \| `dough` |
| Default source | `room` |
| Helper text | “Dough temperature is more accurate, but room temperature is fine.” |
| Persistence | Normalized Celsius + measurement source |

**Supersedes earlier plan note:** oven temperature **is** in Phase C MVP as required `oven_temperature_c` (single oven setpoint only; second oven temp remains deferred).

## Proposed database columns (`public.bakes`)

System / identity (standard):

| Column | Type | Nullability | Notes |
| --- | --- | --- | --- |
| `id` | `uuid` | PK | `gen_random_uuid()` |
| `user_id` | `uuid` | not null | FK → `auth.users(id)` ON DELETE CASCADE |
| `created_at` | `timestamptz` | not null | default `now()` |
| `updated_at` | `timestamptz` | not null | default `now()` |

Required bake fields:

| Column | Type | Nullability | Constraints / notes |
| --- | --- | --- | --- |
| `baked_at` | `timestamptz` | not null | Bake date/time |
| `name` | `text` | not null | Trimmed non-empty |
| `dough_hydration_percent` | `numeric(5,2)` | not null | Typical range ~50–100; validate in app |
| `bulk_fermentation_minutes` | `integer` | not null | `>= 0` |
| `final_proof_minutes` | `integer` | not null | `>= 0` |
| `mixing_method` | `text` | not null | App-constrained enum values (see risks) |
| `shaping_method` | `text` | not null | App-constrained enum values (see risks) |
| `oven_temperature_c` | `numeric(5,1)` | not null | Normalized Celsius; UI may accept °F |
| `baking_time_minutes` | `integer` | not null | `> 0` |
| `result_rating_1_to_5` | `smallint` | not null | Check: `between 1 and 5` |

Optional bake fields:

| Column | Type | Nullability | Constraints / notes |
| --- | --- | --- | --- |
| `fermentation_temperature_c` | `numeric(4,1)` | nullable | Normalized Celsius |
| `fermentation_temperature_source` | `text` | nullable | Check: `room` \| `dough`; NULL if no temp |
| `retardation_minutes` | `integer` | nullable | `>= 0` when present |
| `number_of_folds` | `integer` | nullable | `>= 0` when present |
| `steaming_method` | `text` | nullable | Short free text or later enum |
| `flour_notes` | `text` | nullable | |
| `notes` | `text` | nullable | |

Indexes (proposed): `(user_id, baked_at desc)`, PK on `id`.  
RLS: owner-only (`auth.uid() = user_id`).

## Proposed Swift model

```swift
enum FermentationTemperatureSource: String, Codable, CaseIterable, Equatable {
    case room
    case dough
}

enum MixingMethod: String, Codable, CaseIterable, Equatable {
    // Exact cases TBD at implementation; persisted as raw string matching DB.
}

enum ShapingMethod: String, Codable, CaseIterable, Equatable {
    // Exact cases TBD at implementation; persisted as raw string matching DB.
}

struct Bake: Equatable, Identifiable, Codable {
    let id: UUID
    let userID: UUID
    var bakedAt: Date
    var name: String
    var doughHydrationPercent: Double
    var bulkFermentationMinutes: Int
    var finalProofMinutes: Int
    var mixingMethod: String          // or MixingMethod once cases locked
    var shapingMethod: String         // or ShapingMethod once cases locked
    var ovenTemperatureCelsius: Double
    var bakingTimeMinutes: Int
    var resultRating1To5: Int

    var fermentationTemperatureCelsius: Double?
    var fermentationTemperatureSource: FermentationTemperatureSource?
    var retardationMinutes: Int?
    var numberOfFolds: Int?
    var steamingMethod: String?
    var flourNotes: String?
    var notes: String?

    let createdAt: Date
    var updatedAt: Date
}
```

Coding keys → DB:

| Swift | DB |
| --- | --- |
| `userID` | `user_id` |
| `bakedAt` | `baked_at` |
| `doughHydrationPercent` | `dough_hydration_percent` |
| `bulkFermentationMinutes` | `bulk_fermentation_minutes` |
| `finalProofMinutes` | `final_proof_minutes` |
| `mixingMethod` | `mixing_method` |
| `shapingMethod` | `shaping_method` |
| `ovenTemperatureCelsius` | `oven_temperature_c` |
| `bakingTimeMinutes` | `baking_time_minutes` |
| `resultRating1To5` | `result_rating_1_to_5` |
| `fermentationTemperatureCelsius` | `fermentation_temperature_c` |
| `fermentationTemperatureSource` | `fermentation_temperature_source` |
| `retardationMinutes` | `retardation_minutes` |
| `numberOfFolds` | `number_of_folds` |
| `steamingMethod` | `steaming_method` |
| `flourNotes` | `flour_notes` |
| `createdAt` / `updatedAt` | `created_at` / `updated_at` |

## Validation (required vs optional)

**Required (reject create/update if missing or invalid):**

- `bakedAt` present
- `name` non-empty after trim
- `doughHydrationPercent` present (sensible range enforced in app, e.g. 40–120)
- `bulkFermentationMinutes` ≥ 0
- `finalProofMinutes` ≥ 0
- `mixingMethod` non-empty (must be allowed value once enum locked)
- `shapingMethod` non-empty (must be allowed value once enum locked)
- `ovenTemperatureCelsius` present (after °F→°C if needed)
- `bakingTimeMinutes` > 0
- `resultRating1To5` integer in 1…5

**Optional:**

- All optional columns may be omitted / NULL
- If `fermentationTemperatureCelsius` is set → persist `fermentationTemperatureSource` (UI default `.room`)
- If fermentation temperature empty → both temp and source NULL
- Optional integers (`retardationMinutes`, `numberOfFolds`) if present must be ≥ 0

## Recommended create-bake screen sections

1. **Basics** — Bake date (`baked_at`), Name  
2. **Dough & timing** — Hydration, Bulk fermentation, Final proof  
3. **Process** — Mixing method, Shaping method  
4. **Bake** — Oven temperature (°C/°F toggle), Baking time  
5. **Result** — Rating 1–5  
6. **More details** (collapsed progressive disclosure) — Fermentation temperature + source (default room) + helper text; Retardation; Number of folds; Steaming method; Flour notes; Notes  

Primary CTA: Save bake. Secondary later: Scan loaf (post-create).

## Schema / product risks

1. **`mixing_method` / `shaping_method` / `steaming_method` vocabulary not locked** — DB as `text` is flexible; without agreed enums, AI comparison and analytics stay noisy. Lock picker values before ship.  
2. **`scans.bake_id` has no FK today** — linking loaf scans to `bakes` needs a migration (`bake_id` → `bakes.id`) without breaking starter-only scans.  
3. **Parallel loaf model** — existing `loaf_scans` is user+image-centric, not bake-centric; Phase C must define how journal rows relate to loft analysis history.  
4. **Duration UX** — storing minutes is good; UI should allow hours+minutes to avoid user error on long bulks.  
5. **Temperature dual-unit UX** — oven + fermentation both need clear °C persistence; avoid mixing stored units.  
6. **Required-field friction** — 10 required fields is leaner than Loaflo but still heavy; progressive disclosure and smart defaults (today’s date, last methods) matter for completion rate.  
7. **Roadmap drift** — earlier roadmap `bakes.room_temp_c` / prior plan “no oven temp” are superseded by this field list.

## Remaining Phase C workstreams (not started)

1. `bakes` migration + RLS + `bake_id` FK linkage  
2. Bake journal UI + repository (create / list / detail)  
3. Wire loaf analysis into Home navigation  
4. Previous-bake comparison in `analyze-loaf` + result UI  
5. Tests / Simulator QA with StoreKit / QA Pro override  

## Explicitly deferred (platform / later phases)

- Apple Developer / TestFlight / signed Archive (enrollment pending)  
- Phase D APNs / reminders  
- Loaflo-parity expert fields listed under Deferred above  
