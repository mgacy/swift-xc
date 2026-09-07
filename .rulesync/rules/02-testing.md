---
root: true
targets: ["*"]
description: "Testing conventions for this package"
---

## Testing

Use Apple's **Testing** framework, not XCTest:

```swift
@testable import XCCore
import Testing
```

Describe behavior in the `@Test` decorator rather than the function name:

```swift
@Test("Parser rejects a manifest with no targets")
func rejectsEmptyTargets() throws { }
```

Use `arguments:` for parameterized cases instead of duplicating a test:

```swift
@Test("Recognizes every supported extension", arguments: ["swift", "h", "m"])
func recognizesExtension(_ ext: String) throws { }
```

`Tests/XCCoreTests/` mirrors the structure of `Sources/XCCore/`. When a `@Suite`
trips SwiftLint's `type_body_length`, split it into same-file extensions grouped
by `// MARK:` — SwiftLint counts each extension separately. Promote a group to
`TypeName+Group.swift` once the file approaches `file_length`.
