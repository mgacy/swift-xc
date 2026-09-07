---
root: true
targets: ["*"]
description: "Swift coding conventions for this package"
---

## Swift conventions

Swift 6.2 with strict concurrency. Mark `Sendable` explicitly on types that
cross concurrency boundaries.

### File header

```swift
//
//  FileName.swift
//  TargetName
//
//  Created by Mathew Gacy on M/D/YY.
//  Copyright © YYYY Mathew Gacy. All rights reserved.
//
```

### Naming

- `TypeName.swift` for a primary type
- `TypeName+Extension.swift` / `TypeName+Utils.swift` for extensions
- `TypeName+Protocol.swift` for protocol conformances
- Imports sorted alphabetically

### Access control

Be explicit. `XCCore` is a library target, so every member intended for the
`xc` executable is `public`; use `private` for implementation details,
`fileprivate` rarely, and `package` for cross-target internals.

### Organization

- Group protocol conformances into extensions, one per conformance:
  ```swift
  // MARK: - CustomStringConvertible
  extension Priority: CustomStringConvertible { }
  ```
- Divide types with `// MARK: -` sections
- Use an empty `enum` as a namespace for related constants

### Errors

Use typed throws — one error type per boundary:

```swift
func load(_ url: URL) throws(FileError) -> Data
```

### SwiftLint

Run `mise run lint` before handing work back.
