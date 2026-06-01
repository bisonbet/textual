import Foundation

/// A ``MarkupParser`` implementation backed by Foundation’s Markdown support.
///
/// This parser leverages Foundation’s Markdown support and preserves structure via
/// presentation intents.
///
/// This parser can process its output to expand custom emoji and math expressions into
/// inline attachments.
public struct AttributedStringMarkdownParser: MarkupParser {
  private let baseURL: URL?
  private let options: AttributedString.MarkdownParsingOptions
  private let processor: PatternProcessor

  public init(
    baseURL: URL?,
    options: AttributedString.MarkdownParsingOptions = .init(),
    syntaxExtensions: [SyntaxExtension] = []
  ) {
    self.baseURL = baseURL
    self.options = options
    self.processor = PatternProcessor(syntaxExtensions: syntaxExtensions)
  }

  public func attributedString(for input: String) throws -> AttributedString {
    let linkedImages = LinkedImageProcessor(baseURL: baseURL)
    let preprocessed = linkedImages.preprocess(preprocessDetails(input))
    let attributedString = try processor.expand(
      AttributedString(
        markdown: preprocessed.markdown,
        including: \.textual,
        options: options,
        baseURL: baseURL
      )
    )

    return linkedImages.restore(attributedString, from: preprocessed)
  }

  // Transforms <details>/<summary> HTML blocks into fenced code blocks with a
  // `_textual_details:Summary` language hint so Foundation's markdown parser can
  // represent them as a known PresentationIntent that the rendering layer picks up.
  //
  // The opening fence is made one backtick longer than the longest consecutive
  // backtick run in the body, so a body that itself contains fenced code blocks
  // never prematurely closes the outer fence.
  //
  // <details> tags that appear inside a fenced code block in the source are left
  // alone so users can document the HTML syntax itself. Nested <details> blocks
  // are matched with depth counting; only the outermost block is rewritten here,
  // and the inner block is re-processed when DetailsBlock recursively renders
  // its body via a nested StructuredText.
  private func preprocessDetails(_ input: String) -> String {
    let fenceRanges = fencedCodeBlockRanges(in: input)
    let detailsRanges = outermostDetailsRanges(in: input, ignoring: fenceRanges)

    guard !detailsRanges.isEmpty else { return input }

    var output = String()
    output.reserveCapacity(input.count)
    var cursor = input.startIndex

    for range in detailsRanges {
      output.append(contentsOf: input[cursor..<range.lowerBound])
      if let replacement = transformDetailsBlock(input[range]) {
        output.append(replacement)
      } else {
        output.append(contentsOf: input[range])
      }
      cursor = range.upperBound
    }
    output.append(contentsOf: input[cursor..<input.endIndex])
    return output
  }

  // Walks `input` line by line and returns the ranges of fenced code blocks
  // (CommonMark backtick or tilde fences, up to 3 leading spaces, opener of
  // length >= 3). Each range covers from the opening fence line through the
  // closing fence line. An unclosed fence runs to the end of input.
  private func fencedCodeBlockRanges(in input: String) -> [Range<String.Index>] {
    var ranges: [Range<String.Index>] = []
    var open: (char: Character, length: Int, start: String.Index)?

    var lineStart = input.startIndex
    while lineStart < input.endIndex {
      let lineEnd = input[lineStart...].firstIndex(of: "\n") ?? input.endIndex
      let nextLineStart =
        lineEnd < input.endIndex ? input.index(after: lineEnd) : input.endIndex
      let line = input[lineStart..<lineEnd]

      let leadingSpaces = line.prefix(while: { $0 == " " }).count
      if leadingSpaces <= 3 {
        let body = line.dropFirst(leadingSpaces)
        if let first = body.first, first == "`" || first == "~" {
          let runLength = body.prefix(while: { $0 == first }).count
          if runLength >= 3 {
            if let opener = open {
              // A closing fence must match the opener's char, be at least as
              // long, and have no info string after the run.
              if first == opener.char,
                runLength >= opener.length,
                body.dropFirst(runLength).allSatisfy({ $0 == " " || $0 == "\t" })
              {
                ranges.append(opener.start..<nextLineStart)
                open = nil
              }
            } else {
              open = (first, runLength, lineStart)
            }
          }
        }
      }

      lineStart = nextLineStart
    }
    if let opener = open {
      ranges.append(opener.start..<input.endIndex)
    }
    return ranges
  }

  // Returns outermost balanced `<details>...</details>` ranges in `input`,
  // skipping any open or close tag that overlaps a fenced code block.
  private func outermostDetailsRanges(
    in input: String,
    ignoring fenceRanges: [Range<String.Index>]
  ) -> [Range<String.Index>] {
    let openTag = "<details>"
    let closeTag = "</details>"
    var ranges: [Range<String.Index>] = []
    var cursor = input.startIndex

    while cursor < input.endIndex {
      guard
        let open = nextNonFencedRange(
          of: openTag,
          in: input,
          from: cursor,
          fenceRanges: fenceRanges
        )
      else { break }

      var depth = 1
      var scan = open.upperBound
      var matched: Range<String.Index>?

      while depth > 0 {
        let nextOpen = nextNonFencedRange(
          of: openTag,
          in: input,
          from: scan,
          fenceRanges: fenceRanges
        )
        guard
          let nextClose = nextNonFencedRange(
            of: closeTag,
            in: input,
            from: scan,
            fenceRanges: fenceRanges
          )
        else { break }

        if let nextOpen, nextOpen.lowerBound < nextClose.lowerBound {
          depth += 1
          scan = nextOpen.upperBound
        } else {
          depth -= 1
          if depth == 0 {
            matched = open.lowerBound..<nextClose.upperBound
          } else {
            scan = nextClose.upperBound
          }
        }
      }

      if let matched {
        ranges.append(matched)
        cursor = matched.upperBound
      } else {
        cursor = open.upperBound
      }
    }
    return ranges
  }

  private func nextNonFencedRange(
    of needle: String,
    in input: String,
    from start: String.Index,
    fenceRanges: [Range<String.Index>]
  ) -> Range<String.Index>? {
    var pos = start
    while pos < input.endIndex,
      let range = input.range(of: needle, range: pos..<input.endIndex)
    {
      if let fence = fenceRanges.first(where: { $0.overlaps(range) }) {
        pos = fence.upperBound
        continue
      }
      return range
    }
    return nil
  }

  // Rewrites a single `<details>...</details>` block as a fenced code block
  // tagged with the `_textual_details:` language hint. Returns nil if the
  // block has no `<summary>`, in which case the caller passes it through.
  private func transformDetailsBlock(_ block: Substring) -> String? {
    let openTag = "<details>"
    let closeTag = "</details>"
    let interior = block.dropFirst(openTag.count).dropLast(closeTag.count)

    let trimmed = interior.drop(while: { $0.isWhitespace })
    let summaryOpen = "<summary>"
    let summaryClose = "</summary>"
    guard trimmed.hasPrefix(summaryOpen),
      let close = trimmed.range(of: summaryClose)
    else { return nil }

    let summaryStart = trimmed.index(trimmed.startIndex, offsetBy: summaryOpen.count)
    let summary = String(trimmed[summaryStart..<close.lowerBound])
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacing(/`/, with: "&#96;")
    let body = String(trimmed[close.upperBound...])
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let fence = String(repeating: "`", count: longestBacktickRun(in: body) + 1)
    return "\(fence)_textual_details:\(summary)\n\(body)\n\(fence)"
  }

  // Returns the length of the longest consecutive run of backticks in `string`,
  // with a minimum of 2 so that adding 1 always produces a valid 3-backtick fence.
  private func longestBacktickRun(in string: String) -> Int {
    var maxRun = 2
    var currentRun = 0
    for char in string {
      if char == "`" {
        currentRun += 1
        maxRun = max(maxRun, currentRun)
      } else {
        currentRun = 0
      }
    }
    return maxRun
  }
}

extension MarkupParser where Self == AttributedStringMarkdownParser {
  /// Creates a Markdown parser configured for inline-only syntax.
  public static func inlineMarkdown(
    baseURL: URL? = nil,
    syntaxExtensions: [AttributedStringMarkdownParser.SyntaxExtension] = []
  ) -> Self {
    .init(
      baseURL: baseURL,
      options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace),
      syntaxExtensions: syntaxExtensions
    )
  }

  /// Creates a Markdown parser configured for full-document syntax.
  public static func markdown(
    baseURL: URL? = nil,
    syntaxExtensions: [AttributedStringMarkdownParser.SyntaxExtension] = []
  ) -> Self {
    .init(
      baseURL: baseURL,
      syntaxExtensions: syntaxExtensions
    )
  }
}
