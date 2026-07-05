# SwiftUI Pro - Project Instructions

Review Swift and SwiftUI code for correctness, modern API usage, and adherence to project conventions. Report only genuine problems - do not nitpick or invent issues.

## Core Instructions

- iOS 26 exists, and is the default deployment target for new apps.
- Target Swift 6.2 or later, using modern Swift concurrency.
- As a SwiftUI developer, the user will want to avoid UIKit unless requested.
- Do not introduce third-party frameworks without asking first.
- Break different types up into different Swift files rather than placing multiple structs, classes, or enums into a single file.
- Use a consistent project structure, with folder layout determined by app features.

## Julia Project Rules

### Keyboard shortcuts must be documented — always

Any change that adds, removes, or rebinds a keyboard shortcut MUST update
the in-app keymap page in the same commit: add the row to the sections in
`Julia/Views/HelpView.swift`, and update `README.md` if it mentions the
binding. When reviewing, flag any chord handled in code (`keyboardShortcut`,
`onKeyPress`, hotkey registrations) that is missing from the keymap page.

## Code Review Output Format

Organize findings by file. For each issue:

1. State the file and relevant line(s).
2. Name the rule being violated.
3. Show a brief before/after code fix.

Skip files with no issues. End with a prioritized summary of the most impactful changes.

---

## Modern SwiftUI API

- Always use `foregroundStyle()` instead of `foregroundColor()`.
- Always use `clipShape(.rect(cornerRadius:))` instead of `cornerRadius()`.
- Always use the `Tab` API instead of `tabItem()`.
- Never use the `onChange()` modifier in its 1-parameter variant; either use the variant that accepts two parameters or accepts none.
- Do not use `GeometryReader` if a newer alternative works: `containerRelativeFrame()`, `visualEffect()`, or the `Layout` protocol.
- When designing haptic effects, prefer using `sensoryFeedback()` over older UIKit APIs such as `UIImpactFeedbackGenerator`.
- Use the `@Entry` macro to define custom `EnvironmentValues`, `FocusValues`, `Transaction`, and `ContainerValues` keys.
- Strongly prefer `overlay(alignment:content:)` over the deprecated `overlay(_:alignment:)`.
- Never use `.navigationBarLeading` and `.navigationBarTrailing` for toolbar item placement; use `.topBarLeading` and `.topBarTrailing`.
- Prefer automatic grammar agreement: `Text("^[\(people) person](inflect: true)")`.
- You can fill and stroke a shape with two chained modifiers; no overlay needed (iOS 17+).
- When referencing images from an asset catalog, prefer the generated symbol asset API: `Image(.avatar)` rather than `Image("avatar")`.
- When targeting iOS 26+, SwiftUI has a native `WebView` (requires `import WebKit`).
- `ForEach` over an `enumerated()` sequence: use `ForEach(items.enumerated(), id: \.element.id)` directly.
- When hiding scroll indicators, use `.scrollIndicators(.hidden)` rather than `showsIndicators: false`.
- Never use `Text` concatenation with `+`. Use text interpolation instead.

If using `ObservableObject` is absolutely required, always add `import Combine`.

---

## SwiftUI Views

- Avoid breaking up view bodies using computed properties or methods that return `some View`. Extract them into separate `View` structs instead, placing each into its own file.
- Flag excessively long `body` properties; break into extracted subviews.
- Button actions should be extracted from view bodies into separate methods.
- General business logic should not live inline in `task()`, `onAppear()` or elsewhere in `body`.
- Place view logic into view models or similar for testability.
- Each type (struct, class, enum) should be in its own Swift file.
- Unless full-screen editing is required, prefer `TextField` with `axis: .vertical` over `TextEditor`.
- If a button action can be provided directly as an `action` parameter, do so.
- When rendering SwiftUI views to images, prefer `ImageRenderer` over `UIGraphicsImageRenderer`.
- Use `#Preview` for previews, not the legacy `PreviewProvider` protocol.
- When using `TabView(selection:)`, use a binding to an enum rather than an integer or string.

### Animating Views

- Prefer the `@Animatable` macro over creating `animatableData` manually.
- Never use `animation(_ animation: Animation?)`; always provide a value to watch.
- Chain animations using a `completion` closure passed to `withAnimation()`:

```swift
Button("Animate Me") {
    withAnimation {
        scale = 2
    } completion: {
        withAnimation {
            scale = 1
        }
    }
}
```

---

## Data Flow, Shared State, and Property Wrappers

### Shared State

- `@Observable` classes must be marked `@MainActor` unless the project has Main Actor default actor isolation.
- All shared data should use `@Observable` classes with `@State` (for ownership) and `@Bindable` / `@Environment` (for passing).
- Strongly prefer not to use `ObservableObject`, `@Published`, `@StateObject`, `@ObservedObject`, or `@EnvironmentObject` unless unavoidable.

### Local State

- `@State` should be marked `private` and only owned by the view that created it.
- For expensive-to-recompute data (e.g. `CIContext`), `@State` can be used as a cache.

### Bindings

- Avoid creating bindings using `Binding(get:set:)` in view body code. Use `onChange()` instead.
- For numeric `TextField` input, use the `format` initializer: `TextField("Enter your score", value: $score, format: .number)` with appropriate `.keyboardType()`.

### Working with Data

- Prefer making structs conform to `Identifiable` rather than using `id: \.someProperty`.
- Never use `@AppStorage` inside an `@Observable` class.

### SwiftData

- For count-only queries, consider `ModelContext.fetchCount()` with a fetch descriptor.

### SwiftData with CloudKit

- Never use `@Attribute(.unique)`.
- Model properties must have default values or be marked optional.
- All relationships must be marked optional.

---

## Navigation and Presentation

- Use `NavigationStack` or `NavigationSplitView`; flag all use of deprecated `NavigationView`.
- Prefer `navigationDestination(for:)` to specify destinations; flag old `NavigationLink(destination:)` pattern.
- Never mix `navigationDestination(for:)` and `NavigationLink(destination:)` in the same hierarchy.
- `navigationDestination(for:)` must be registered once per data type.

### Alerts, Confirmation Dialogs, and Sheets

- Always attach `confirmationDialog()` to the UI that triggers the dialog (Liquid Glass animations).
- Single "OK" button alerts can omit actions: `.alert("Dismiss Me", isPresented: $isShowingAlert) { }`.
- For optional data sheets, prefer `sheet(item:)` over `sheet(isPresented:)`.
- Use `sheet(item: $someItem, content: SomeView.init)` over verbose closure syntax.

---

## Accessibility

- Respect user accessibility settings for fonts, colors, animations.
- Do not force specific font sizes. Prefer Dynamic Type (`.font(.body)`, `.font(.headline)`, etc.).
- For custom font sizes: use `@ScaledMetric` (iOS 18-) or `.font(.body.scaled(by:))` (iOS 26+).
- Flag images with unclear VoiceOver readings. Use `Image(decorative:)` or `accessibilityHidden()` for decorative images, or attach `accessibilityLabel()`.
- If "Reduce Motion" is enabled, replace motion-based animations with opacity.
- For complex/changing button labels, use `accessibilityInputLabels()` for Voice Control.
- Buttons with image labels must always include text: `Button("Label", systemImage: "plus", action: myAction)`.
- Respect `.accessibilityDifferentiateWithoutColor` by showing variations beyond just color.
- Same applies to `Menu`: `Menu("Options", systemImage: "ellipsis.circle") { }` is better than image-only.
- Never use `onTapGesture()` unless you need tap location or count. Use `Button` instead.
- If `onTapGesture()` is required, add `.accessibilityAddTraits(.isButton)`.

---

## Design

### Uniform Design

Place standard fonts, sizes, colors, stack spacing, padding, rounding, animation timings into a shared enum of constants for consistency.

### Flexible, Accessible Design

- Never use `UIScreen.main.bounds`; prefer `containerRelativeFrame()`, `visualEffect()`, or (if needed) `GeometryReader`.
- Avoid fixed frames unless content fits neatly; prefer flexibility for different device sizes and Dynamic Type.
- Apple's minimum tap area: 44x44.

### Standard System Styling

- Use `ContentUnavailableView` when data is missing or empty.
- With `searchable()`, use `ContentUnavailableView.search` (auto-includes search term).
- For icon + text horizontally, prefer `Label` over `HStack`.
- Prefer system hierarchical styles (secondary/tertiary) over manual opacity.
- In `Form`, wrap controls like `Slider` in `LabeledContent`.
- `RoundedRectangle` defaults to `.continuous` style.

### Designs for Everyone

- Use `bold()` instead of `fontWeight(.bold)`.
- Only use `fontWeight()` for non-bold weights when there's an important reason.
- Avoid hard-coded padding and stack spacing unless requested.
- Avoid UIKit colors (`UIColor`) in SwiftUI; use SwiftUI `Color` or asset catalog colors.
- `.caption2` is extremely small; `.caption` should be used carefully.

---

## Performance

- When toggling modifier values, prefer ternary expressions over if/else view branching.
- Avoid `AnyView` unless absolutely required. Use `@ViewBuilder`, `Group`, or generics.
- For opaque, static, solid `ScrollView` backgrounds, use `scrollContentBackground(.visible)`.
- Breaking views into dedicated structs is more efficient than computed properties/methods.
- Keep view initializers small and simple; move work to `task()` modifiers.
- Assume `body` is called frequently; move sorting/filtering logic out.
- Avoid creating formatter properties; use `Text(value, format:)` APIs.
- Avoid expensive inline transforms in `List`/`ForEach` initializers.
- Derive transformed data from source-of-truth using `let`, or cache in `@State` with explicit invalidation.
- For large data sets in `ScrollView`, use `LazyVStack`/`LazyHStack`.
- Prefer `task()` over `onAppear()` for async work (auto-cancellation).
- Avoid storing escaping `@ViewBuilder` closures; store built view results:

```swift
// Preferred: store the built view value
struct CardView<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading) {
            content
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: 8))
    }
}
```

---

## Swift

- Prefer Swift-native string methods: `replacing("a", with: "b")` not `replacingOccurrences(of:with:)`.
- Prefer modern Foundation API: `URL.documentsDirectory`, `appending(path:)`.
- Never use C-style number formatting like `String(format:)`. Use `FormatStyle` APIs.
- Prefer static member lookup: `.circle` rather than `Circle()`.
- Avoid force unwraps (`!`) and force `try`. Use `if let`, `guard let`, nil-coalescing, or `try?`/`do-catch`.
- Filtering text based on user-input: use `localizedStandardContains()`.
- Prefer `Double` over `CGFloat`, except with optionals or `inout`.
- Use `count(where:)` rather than `filter().count`.
- Prefer `Date.now` over `Date()`.
- `import SwiftUI` automatically imports `UIKit`/`AppKit` as needed.
- For person names, use `PersonNameComponents` with modern formatting.
- If data is repeatedly sorted identically, make the type conform to `Comparable`.
- Avoid manual date formatting strings if possible. Use "y" not "yyyy" for years in user display.
- For string-to-date conversion: `Date(myString, strategy: .iso8601)`.
- Flag silently swallowed user-triggered errors.
- Prefer `if let value {` shorthand over `if let value = value {`.
- Omit return for single expression functions. Use `if` and `switch` as expressions:

```swift
var tileColor: Color {
    if isCorrect {
        .green
    } else {
        .red
    }
}
```

### Swift Concurrency

- Prefer `async`/`await` over closure-based APIs.
- Never use Grand Central Dispatch. Use modern Swift concurrency.
- Use `Task.sleep(for:)` not `Task.sleep(nanoseconds:)`.
- Flag mutable shared state not protected by an actor or `@MainActor`.
- Assume strict concurrency rules; flag `@Sendable` violations and data races.
- Check if project has Main Actor default isolation before flagging `MainActor.run()`.
- `Task.detached()` is often a bad idea; check usage carefully.

---

## Hygiene

- Never include secrets (API keys) in the repository.
- Code comments should be present where logic isn't self-evident.
- Unit tests should exist for core application logic.
- Never use `@AppStorage` for usernames, passwords, or sensitive data. Use the keychain.
- If SwiftLint is configured, it should return no warnings or errors.
- If using Localizable.xcstrings, prefer symbol keys with `extractionState` set to "manual".
- If Xcode MCP is configured, prefer its tools (e.g., `RenderPreview`, `DocumentationSearch`).

---

*Based on SwiftUI Pro by Paul Hudson (MIT License)*
