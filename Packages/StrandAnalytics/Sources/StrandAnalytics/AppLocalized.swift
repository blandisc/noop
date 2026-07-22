import Foundation

// The insight detectors surface user-facing es-MX copy whose English key lives in the *app's*
// String Catalog, so at runtime the translation must be resolved against `Bundle.main` — an
// Apple-only concern. But this package's test lane compiles on Linux (swift-corelibs-foundation),
// where neither the `bundle:` overload of `String(localized:)` nor `String.LocalizationValue`
// exists. `appLocalized` bridges the two with a platform-split overload: on Apple it does the real
// catalog lookup (behaviour unchanged); off-device it just returns the key verbatim so the package
// builds and its math tests run. Same call site, same interpolation, on both platforms.
#if canImport(Darwin)
@inline(__always)
func appLocalized(_ value: String.LocalizationValue) -> String {
    String(localized: value, bundle: .main)
}
#else
@inline(__always)
func appLocalized(_ value: String) -> String { value }
#endif
