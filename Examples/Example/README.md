# Example

A small Xcode fixture for developing `xc`, containing an iOS app and two local
Swift packages. Its project layout exercises package discovery, test-plan
membership, and execution through both SwiftPM and Xcode.

## Requirements

- Xcode 26.5 or later and an iOS 26.5 or later simulator for the app scheme.
- macOS 26 or later for running SharedKit tests directly with SwiftPM.

The example is independent of the repository's root Swift package. Root
`swift build` and `swift test` commands build and test `xc`; use the commands
below to exercise the example.

## Commands

Run these commands from `Examples/Example`.

List the schemes and available destinations:

```sh
xcodebuild -list -project Example.xcodeproj
xcodebuild -showdestinations -project Example.xcodeproj -scheme Example
```

Set `EXAMPLE_DESTINATION` to an eligible destination from that output, such as
`platform=iOS Simulator,id=<simulator-UUID>`, then run the package test plan:

```sh
xcodebuild test -project Example.xcodeproj -scheme CI \
  -testPlan Example -destination "$EXAMPLE_DESTINATION" \
  -derivedDataPath .deriveddata
```

The app scheme builds the app before running the same package tests:

```sh
xcodebuild test -project Example.xcodeproj -scheme Example \
  -testPlan Example -destination "$EXAMPLE_DESTINATION" \
  -derivedDataPath .deriveddata
```

Select one package test:

```sh
xcodebuild test -project Example.xcodeproj -scheme CI \
  -testPlan Example -destination "$EXAMPLE_DESTINATION" \
  -derivedDataPath .deriveddata \
  -only-testing:SharedKitTests/GreeterTests/greetingIncludesName
```

Run SharedKit on macOS:

```sh
swift test --package-path Packages/SharedKit
```

To exercise the storage probe with this checkout's CLI, run from the repository
root:

```sh
swift build
(cd Examples/Example && ../../.build/debug/xc run)
```

The probe resolves the enclosing `swift-xc` Git worktree as its workspace.
Workspace-local probe paths and retained artifact identity therefore belong to
that worktree, even when invoked from this directory.

## Fixture structure

- `Packages` is a synchronized folder group in the Xcode project. The app links
  the SharedKit and MobileKit products; the test plan references the packages
  through relative `container:Packages/...` paths.
- `Example.xctestplan` includes `SharedKitTests`, `SharedKitEnvironmentTests`,
  and `MobileKitTests`. Both shared schemes reference that plan. `CI` has no
  build entries; `Example` builds the app.
- SharedKit supports iOS and macOS. Its environment-mutating test lives in a
  separate test target.
- MobileKit imports UIKit and depends on SharedKit. Run its tests through Xcode
  on an iOS simulator.
- `ExampleTests` and `ExampleUITests` retain the template app test targets. They
  are outside the shared test plan and do not run with the commands above.

Device builds require selecting a development team in Xcode. Simulator builds
do not require a personal team to be stored in the project.

## Provenance

Imported from `swift-xc-test-project` at commit
`cb056058f450b84ad6b3cfa7304b78e3bbbeb94e`, with the project, app, and native test
targets renamed from `XCTest` to `Example`.
