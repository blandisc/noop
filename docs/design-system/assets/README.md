# Assets

Brand and icon assets for the Strand / NOOP design system. Copied from the app's
asset catalogs and `docs/assets/`.

## `brand/`

| File | Notes |
|---|---|
| `logo.svg` | App logo (vector) |
| `banner.svg` | README / marketing banner (vector) |

## `app-icon/`

NOOP ships on **iOS only**, where the app icon is a single 1024×1024 image (iOS renders
every smaller size from it):

| File | Size | Source |
|---|---|---|
| `icon_1024.png` | 1024×1024 | iOS app icon (`CenitApp` catalog) |

> **Legacy macOS set.** The `icon_16x16…icon_512x512` (`@1x/@2x`) PNGs alongside it are
> leftovers from the retired macOS app's multi-size icon set. The macOS app and its
> asset catalog were removed (FER-143/FER-144); these PNGs are **not** the active icon
> and survive only as stale copies in this folder.

> **Canonical source** (don't edit this copy — edit the catalog, then re-copy):
> - iOS icon: `CenitApp/Resources/Assets.xcassets/AppIcon.appiconset/`
> - Brand SVGs: `docs/assets/`
