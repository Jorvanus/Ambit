# Ambit

Personal iOS travel itinerary app (SwiftUI, SwiftData, MapKit). Local-only, no backend.

## Distribution

**This app is not going on the App Store.** It is a personal app installed on the owner's own
devices from Xcode with a development profile. Do not spend effort on App Store readiness:
no App Store Connect, distribution profiles, TestFlight, privacy nutrition labels, review
guidelines, screenshots/marketing, or release/versioning workflows unless explicitly asked.
That also means bundle IDs and App Group names are not permanent; they can change if needed.

## Build

- Xcode 27 / iOS 27 deployment target, Swift 6. The project is generated: edit `project.yml`,
  then run `xcodegen generate` (`Ambit.xcodeproj` is gitignored). Re-run it after adding or
  removing source files.
- Signing: team `337KNRL5L8`, automatic. Device builds need `-allowProvisioningUpdates`.
  App `com.aarongbaxter.AmbitTrips`, extension `.Share`, App Group `group.com.aarongbaxter.AmbitTrips`.
- Simulators: select by ID (name lookups fail with several runtimes installed).

## Data

SwiftData with a versioned schema (`Ambit/Models/SchemaVersions.swift`). A new non-optional
`@Model` property needs an inline default or existing rows crash on load.
