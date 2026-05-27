import SwiftUI
import Testing

@testable import Textual

@MainActor
extension TextFragment<AttributedString> {
  struct TextBuilderTests {
    private static func makeAttributedString(
      runCount: Int,
      colors: [Color] = [.red, .blue, .green, .orange, .purple]
    ) -> AttributedString {
      var result = AttributedString()
      for index in 0 ..< runCount {
        var piece = AttributedString("token-\(index) ")
        piece.foregroundColor = colors[index % colors.count]
        result.append(piece)
      }
      return result
    }

    @Test func empty() {
      let builder = TextFragment<AttributedString>.TextBuilder(
        AttributedString(),
        environment: TextEnvironmentValues()
      )
      #expect(type(of: builder.text) == Text.self)
    }

    @Test func plainSingleRun() {
      let builder = TextFragment<AttributedString>.TextBuilder(
        AttributedString("hello world"),
        environment: TextEnvironmentValues()
      )
      #expect(type(of: builder.text) == Text.self)
    }

    /// A pathologically large run count that would overflow the SwiftUI layout stack
    /// under the previous `Text("\(prev)\(next)")` reduction. We can't probe the
    /// resulting Text-tree depth from outside SwiftUI, but we can at least confirm that
    /// construction itself remains O(N) and doesn't recurse N levels — when it does,
    /// it shows up as `EXC_BAD_ACCESS` here, not a passing test.
    @Test func largeRunCountConstructsCleanly() {
      let attributed = Self.makeAttributedString(runCount: 5000)
      let builder = TextFragment<AttributedString>.TextBuilder(
        attributed,
        environment: TextEnvironmentValues()
      )
      #expect(type(of: builder.text) == Text.self)
    }

    @Test func plainRunsAreCoalescedAcrossSizeChanges() {
      let attributed = Self.makeAttributedString(runCount: 100)
      let builder = TextFragment<AttributedString>.TextBuilder(
        attributed,
        environment: TextEnvironmentValues()
      )
      builder.sizeChanged(CGSize(width: 320, height: 480), environment: TextEnvironmentValues())
      builder.sizeChanged(CGSize(width: 480, height: 320), environment: TextEnvironmentValues())
      #expect(type(of: builder.text) == Text.self)
    }

    @Test func runsWithLinks() {
      var attributed = AttributedString("Visit ")
      var linkRun = AttributedString("the example site")
      linkRun.link = URL(string: "https://example.com")
      attributed.append(linkRun)
      attributed.append(AttributedString(" for details. "))

      var trailingLink = AttributedString("Or here")
      trailingLink.link = URL(string: "https://example.org")
      attributed.append(trailingLink)
      attributed.append(AttributedString("."))

      let builder = TextFragment<AttributedString>.TextBuilder(
        attributed,
        environment: TextEnvironmentValues()
      )
      #expect(type(of: builder.text) == Text.self)
    }

    /// Stress-tests the balanced concatenation path. Many link-bearing runs each force
    /// a separate Text node; a left-fold concat would build a `ConcatenatedTextStorage`
    /// tree of depth = link count and re-introduce the 2024-class recursion crash for
    /// pathological link-list content. Pairwise merge keeps the tree O(log N) deep.
    @Test func manyLinkRunsConstructCleanly() {
      var attributed = AttributedString()
      for index in 0 ..< 2000 {
        var prose = AttributedString("see ")
        prose.foregroundColor = .secondary
        attributed.append(prose)

        var link = AttributedString("link-\(index)")
        link.link = URL(string: "https://example.com/\(index)")
        attributed.append(link)

        attributed.append(AttributedString(", "))
      }

      let builder = TextFragment<AttributedString>.TextBuilder(
        attributed,
        environment: TextEnvironmentValues()
      )
      #expect(type(of: builder.text) == Text.self)
    }

    @Test func balancedConcatenationOfEmptyArrayIsEmpty() {
      let result = Text.balancedConcatenation(of: [])
      #expect(type(of: result) == Text.self)
    }

    @Test func balancedConcatenationOfSingleElementReturnsThatElement() {
      let only = Text("only")
      let result = Text.balancedConcatenation(of: [only])
      #expect(type(of: result) == Text.self)
    }
  }
}
