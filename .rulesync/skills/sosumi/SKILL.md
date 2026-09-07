---
name: sosumi
description: Fetches Apple documentation as Markdown via Sosumi. Use for Apple API reference, Human Interface Guidelines, WWDC transcripts, and external Swift-DocC pages.
targets: ["*"]
---

# Sosumi Skill

Use this skill to reliably fetch Apple docs as Markdown when coding agents need precise API details.

## When to Use

Use Sosumi when the request involves any of the following:

- Apple platform APIs (`Swift`, `SwiftUI`, `UIKit`, `AppKit`, `Foundation`, etc.)
- API signatures, availability, parameter behavior, or return semantics
- Human Interface Guidelines questions
- WWDC session transcript lookup
- External Swift-DocC documentation (for example, GitHub Pages or Swift Package Index hosts)

## Core Workflow

**Prefer the CLI.** Use it whenever `sosumi` is on `PATH`; the HTTP fallback is
for when it is not.

```bash
sosumi search "SwiftData"                                           # find the path when you don't know it
sosumi fetch /documentation/swift/array                             # fetch by path
sosumi fetch https://developer.apple.com/documentation/swift/array  # or by Apple URL — no host swap needed
sosumi fetch /videos/play/wwdc2021/10133
```

Search first when you do not know the exact path, then fetch the best match. Prefer a specific symbol page over a broad top-level page for implementation questions. Both subcommands accept `--json` when you need to select from results programmatically rather than read them.

`sosumi --help` and `sosumi <command> --help` are authoritative for anything beyond the above.

## HTTP Fallback

Without the CLI, request the same paths from `sosumi.ai` — keep any `developer.apple.com` path and swap the host:

- Apple: `https://developer.apple.com/documentation/swift/array`
- Markdown: `https://sosumi.ai/documentation/swift/array`

## Paths

Pass these to `sosumi fetch`, or append to `https://sosumi.ai` for the HTTP fallback.

| Content | Path pattern | Example |
|---|---|---|
| Apple API reference | `/documentation/{framework}/{symbol}` | `/documentation/swiftui/view` |
| Human Interface Guidelines | `/design/human-interface-guidelines/{topic}` | `/design/human-interface-guidelines/foundations/color` |
| Apple video transcripts | `/videos/play/{collection}/{id}` | `/videos/play/wwdc2021/10133` |
| External Swift-DocC | `/external/{full-https-url}` | `/external/https://apple.github.io/swift-argument-parser/documentation/argumentparser/` |

## Best Practices

- Keep source links in answers so users can verify details quickly.
- Use Sosumi paths directly in responses whenever referencing Apple documentation pages.

## Troubleshooting

### 404 or sparse output

- The path may be incorrect or too broad.
- Run `sosumi search` first, then fetch a specific result path.

### External page cannot be fetched

- The host may block access via `robots.txt` or `X-Robots-Tag` directives.
- Try another canonical page URL for the same symbol.
