# Writing Swift in longbook

Apple's guidance is a requirement here, not a suggestion. Before writing or reviewing Swift, read the
section that matches the change. If your environment has the `swiftui-expert-skill`, `swift-concurrency`
and `apple-hig` skills, load them and open the reference named below; otherwise use Apple's documentation
for the same topic.

| The change touches | Read first |
|---|---|
| `@State`, `@Observable`, bindings, data flow | swiftui-expert-skill `state-management.md`, `environment-patterns.md` |
| A view's `body`, extracting subviews | `view-structure.md`, `modifier-patterns.md` |
| Layout, stacks, sizes, both platforms | `layout-best-practices.md`, `macos-views.md`, `macos-window-styling.md` |
| Lists, scrolling, search | `list-patterns.md`, `scroll-patterns.md` |
| Sheets, navigation, toolbars, menus | `sheet-navigation-patterns.md`, `toolbar-patterns.md`, `macos-scenes.md` |
| Focus, keyboard, Tab order | `focus-patterns.md` |
| Animation | `animation-basics.md`, `animation-transitions.md` |
| Charts | `charts.md`, `charts-accessibility.md` |
| Text, labels, localization | `text-patterns.md`, `localization.md` |
| Glass and newer APIs | `liquid-glass.md`, `latest-apis.md`, `soft-deprecation.md` |
| Slow screens | `performance-patterns.md`, `image-optimization.md` |
| `async`/`await`, actors, `@MainActor`, `Sendable`, tasks | swift-concurrency (its `_index.md` routes to the topic) |
| Any control, sheet, sign-in, alert or copy | apple-hig for that component, then `apple-hig-longbook.md` here |

## Rules that come out of that guidance here

- Keep a view's `body` short: split long modifier chains and large forms into subviews. Xcode 26 cannot
  type-check `RenewalFormView`'s body in time, which is why CI skips the app build until Xcode 27.
- Targets are iOS 17 and macOS 14: an API newer than that goes behind `#available` with a fallback.
- The pull request names what was read, as a line: `Checked against: <skill> <reference>, …`.
