---
root: true
targets: ["*"]
description: "Documentation and comment standards"
---

## Documentation

Follow Apple's conventions — doc comments feed Xcode Quick Help and DocC, so
their structure is a contract rather than a style preference.

```swift
/// Returns the clamped value.
///
/// - Parameters:
///   - value: The value to clamp.
///   - minValue: The minimum value.
///   - maxValue: The maximum value.
/// - Returns: The clamped value.
/// - Throws: `XCError.invalidRange` if `maxValue` precedes `minValue`.
```

Document return values and throwing behavior on every declaration that has
them, and include a usage example for a non-obvious API.

### What not to write

- **Document the local contract, not specific callers.** A doc says what the
  declaration *is* — inputs, outputs, throws, invariants. Naming a caller rots
  the moment that code moves.
- **Rot test.** Before keeping a sentence, ask whether it would still be true if
  every caller in this codebase were replaced. If not, delete it.
- **Write for the caller, not future-you.** Cut rationale for the road not
  taken, "not yet" snapshots of other code, `- Note:` TODOs, and editorializing
  ("crucially", "defensive").
- **Don't write the diff.** State what the declaration is, not how it differs
  from what it replaced ("now returns nil", "no longer throws"). Test: would you
  write this sentence if the code had always looked this way?
