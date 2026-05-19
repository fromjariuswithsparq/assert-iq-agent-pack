---
applyTo: "**/*.{cs,xaml}"
description: "Requirement → code → test traceability enforcement."
---

# Traceability instructions

**When this applies:** introducing or modifying production C# / XAML code
(`**/*.{cs,xaml}`) that implements a tracked work item. Copilot loads via
`applyTo`; Claude Code: apply whenever the user adds or changes C#/XAML
code tied to a work item.

When introducing new functions, classes, or modules that implement a tracked
work item, attach a trace comment in the project's idiomatic style:

- TypeScript / JavaScript: JSDoc `@qi-trace`
- Python: docstring `:qi-trace:`
- Java / Kotlin: Javadoc `@qi-trace`
- C# (general): XML doc element `/// <qi-trace … />`
- .NET MAUI / Xamarin (C#): XML doc element `/// <qi-trace … />` on the code-behind class or ViewModel
- .NET MAUI / Xamarin (XAML): XML comment `<!-- qi-trace: -->` immediately above the root element
- Go: comment block `// qi-trace:`

The trace must include:
- `work-item`: the ADO work item ID or Jira issue key
- `acceptance-criteria`: the AC reference (e.g., `AC-2`)
- `risk-tier`: `low | medium | high`
- `test-coverage`: relative path(s) to the covering test file(s)

When a function is modified, do not silently drop or alter an existing trace.
If the change invalidates the trace, flag it and ask the user to confirm the
new linkage.

## .NET MAUI & Xamarin.UITest specifics

For .NET MAUI pages, controls, and ViewModels, place the XML doc trace on the
class declaration in the code-behind or ViewModel file:

```csharp
/// <qi-trace
///   work-item="AB#1234"
///   acceptance-criteria="AC-3"
///   risk-tier="medium"
///   test-coverage="tests/UI/LoginPageTests.cs" />
public partial class LoginPage : ContentPage { … }
```

For XAML files, add an XML comment directly above the root element:

```xml
<!-- qi-trace: work-item="AB#1234" acceptance-criteria="AC-3" risk-tier="medium" test-coverage="tests/UI/LoginPageTests.cs" -->
<ContentPage xmlns="http://schemas.microsoft.com/dotnet/2021/maui" …>
```

For Xamarin.UITest test classes, place the trace on the test class and on each
`[Test]` method that covers an acceptance criterion:

```csharp
/// <qi-trace
///   work-item="AB#1234"
///   acceptance-criteria="AC-3"
///   risk-tier="medium"
///   test-coverage="tests/UI/LoginPageTests.cs" />
[TestFixture]
public class LoginPageTests { … }
```

- `test-coverage` for MAUI/Xamarin should point to the Xamarin.UITest project file
  or specific test class, not just a folder.
- When a XAML page and its code-behind both carry a trace, they must reference
  the **same** `work-item` and `acceptance-criteria`; flag any mismatch.
