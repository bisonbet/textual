import SwiftUI
import Testing

@testable import Textual

struct MermaidCodeBlockTests {
  // MARK: - Block Parsing

  @Test func mermaidBlockIsParsedAsCodeBlock() throws {
    // given
    let attributedString = try AttributedString(
      markdown: """
        ```mermaid
        flowchart LR
            A --> B
        ```
        """
    )

    // when
    let blocks = attributedString.blockRuns()

    // then
    #expect(blocks.count == 1)
    #expect(blocks[0].intent?.kind == .codeBlock(languageHint: "mermaid"))
  }

  @Test func mermaidBlockWithSurroundingContent() throws {
    // given
    let attributedString = try AttributedString(
      markdown: """
        # Architecture

        ```mermaid
        flowchart TB
            A["Service A"] --> B["Service B"]
        ```

        Some text after the diagram.
        """
    )

    // when
    let blocks = attributedString.blockRuns()

    // then
    #expect(blocks.count == 3)
    #expect(blocks[0].intent?.kind == .header(level: 1))
    #expect(blocks[1].intent?.kind == .codeBlock(languageHint: "mermaid"))
    #expect(blocks[2].intent?.kind == .paragraph)
  }

  @Test func mermaidBlockContentIsPreserved() throws {
    // given
    let source = "sequenceDiagram\n    A->>B: Hello\n"
    let attributedString = try AttributedString(
      markdown: """
        ```mermaid
        \(source)```
        """
    )

    // when
    let blocks = attributedString.blockRuns()
    let content = String(attributedString[blocks[0].range].characters[...])

    // then
    #expect(content == source)
  }

  @Test func multipleMermaidBlocks() throws {
    // given
    let attributedString = try AttributedString(
      markdown: """
        ```mermaid
        flowchart LR
            A --> B
        ```

        ```mermaid
        sequenceDiagram
            A->>B: Hello
        ```
        """
    )

    // when
    let blocks = attributedString.blockRuns()

    // then
    #expect(blocks.count == 2)
    #expect(blocks[0].intent?.kind == .codeBlock(languageHint: "mermaid"))
    #expect(blocks[1].intent?.kind == .codeBlock(languageHint: "mermaid"))
  }

  @Test func mermaidBlockDoesNotAffectOtherCodeBlocks() throws {
    // given
    let attributedString = try AttributedString(
      markdown: """
        ```swift
        let x = 1
        ```

        ```mermaid
        flowchart LR
            A --> B
        ```

        ```python
        print("hello")
        ```
        """
    )

    // when
    let blocks = attributedString.blockRuns()

    // then
    #expect(blocks.count == 3)
    #expect(blocks[0].intent?.kind == .codeBlock(languageHint: "swift"))
    #expect(blocks[1].intent?.kind == .codeBlock(languageHint: "mermaid"))
    #expect(blocks[2].intent?.kind == .codeBlock(languageHint: "python"))
  }

  // MARK: - MermaidRenderer

  @Test @MainActor func rendererIsSingleton() {
    let a = MermaidRenderer.shared
    let b = MermaidRenderer.shared
    #expect(a === b)
  }

  #if canImport(WebKit)
    @Test @MainActor func rendererProducesDiagram() async {
      let diagram = await MermaidRenderer.shared.render(
        source: "flowchart LR\n    A --> B",
        width: 400
      )

      #expect(diagram != nil)
      if let diagram {
        #expect(diagram.size.width > 0)
        #expect(diagram.size.height > 0)
        #expect(diagram.cgImage.width > 0)
        #expect(diagram.cgImage.height > 0)
      }
    }

    @Test @MainActor func rendererCachesResults() async {
      let source = "flowchart LR\n    X --> Y"

      let first = await MermaidRenderer.shared.render(source: source, width: 400)
      let second = await MermaidRenderer.shared.render(source: source, width: 400)

      #expect(first != nil)
      #expect(second != nil)
      if let first, let second {
        #expect(first.cgImage === second.cgImage)
      }
    }

    @Test @MainActor func rendererReturnsNilForInvalidSource() async {
      let diagram = await MermaidRenderer.shared.render(
        source: "this is not valid mermaid syntax %%%",
        width: 400
      )

      #expect(diagram == nil)
    }

    @Test @MainActor func rendererSupportsDarkTheme() async {
      let diagram = await MermaidRenderer.shared.render(
        source: "flowchart LR\n    A --> B",
        width: 400,
        theme: "dark"
      )

      #expect(diagram != nil)
    }

    @Test @MainActor func rendererHandlesSequenceDiagram() async {
      let diagram = await MermaidRenderer.shared.render(
        source: """
          sequenceDiagram
              A->>B: Hello
              B-->>A: Hi
          """,
        width: 400
      )

      #expect(diagram != nil)
      if let diagram {
        #expect(diagram.size.width > 0)
        #expect(diagram.size.height > 0)
      }
    }

    // Two concurrent renders of different sources must both succeed — the
    // shared render lock serializes them through the same WebView without
    // corrupting each other's output.
    @Test @MainActor func rendererHandlesConcurrentRenders() async {
      async let first = MermaidRenderer.shared.render(
        source: "flowchart LR\n    Concurrent1 --> Done",
        width: 400
      )
      async let second = MermaidRenderer.shared.render(
        source: "flowchart LR\n    Concurrent2 --> Done",
        width: 400
      )

      let (a, b) = await (first, second)
      #expect(a != nil)
      #expect(b != nil)
      if let a, let b {
        #expect(a.cgImage !== b.cgImage)
      }
    }

    // Rendering the same source twice with different themes must succeed for
    // both — exercises applyTheme between calls and confirms cache keys
    // include theme so each variant gets its own entry.
    @Test @MainActor func rendererHandlesThemeToggle() async {
      let source = "flowchart LR\n    Light --> Dark"

      let light = await MermaidRenderer.shared.render(
        source: source,
        width: 400,
        theme: "default"
      )
      let dark = await MermaidRenderer.shared.render(
        source: source,
        width: 400,
        theme: "dark"
      )

      #expect(light != nil)
      #expect(dark != nil)
      if let light, let dark {
        #expect(light.cgImage !== dark.cgImage)
      }
    }
  #endif
}
