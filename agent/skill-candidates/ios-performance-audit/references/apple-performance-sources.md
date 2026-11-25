# Apple performance source routing

Review date: 2026-10-03. These links route current investigation, not a frozen
manual or a mandatory full reading list. Reopen the relevant primary source when
an API, deployment target or Instruments workflow materially affects the task.

- SwiftUI update causes, long bodies and correlated CPU work:
  [Optimize SwiftUI performance with Instruments, WWDC25](https://developer.apple.com/videos/play/wwdc2025/306/).
  Its accessible transcript was reviewed for this skill. Correlation and
  before/after investigation inform the workflow; no universal numeric pass
  threshold is asserted.
- General SwiftUI diagnosis:
  [Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance).
- Non-SwiftUI waits and responsiveness:
  [Improving app responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness).
- Scroll composition:
  [Creating performant scrollable stacks](https://developer.apple.com/documentation/swiftui/creating-performant-scrollable-stacks).

Conceptually reviewed alongside
[OpenAI’s SwiftUI performance audit](https://github.com/openai/plugins/blob/main/plugins/build-ios-apps/skills/swiftui-performance-audit/SKILL.md).
This is an original portable workflow, not an installed upstream package or a
claim that every upstream helper/reference has been executable-tested. It uses
the host’s available tools and the project’s existing gates.
