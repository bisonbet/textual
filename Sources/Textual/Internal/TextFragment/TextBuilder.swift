import SwiftUI

// MARK: - Overview
//
// TextBuilder constructs SwiftUI.Text from attributed content with inline attachments.
// It caches Text values keyed by attachment sizes to avoid unnecessary rebuilds during
// resize. When the container size changes, attachment sizes are recomputed and the cache
// is consulted. If the new sizes hash to the same key, the cached Text is reused.
//
// The cache key is derived from the hash of [AttachmentKey: CGSize]. Since attachment
// sizes often remain constant or repeat during incremental resize (e.g., window resizing),
// this compact key enables effective caching without storing the full proposal or
// attributed string. The cache has a count limit of 10 to prevent unbounded growth.
//
// Runs with attachments are converted to placeholder images sized by the attachment's
// sizeThatFits(_:in:) result. Placeholders are tagged with AttachmentAttribute so overlays
// can identify and render the actual attachment views at the resolved layout positions.
//
// MARK: - Recursion-safe Text construction
//
// Only attachment placeholders and link runs need to be standalone Text nodes — they
// rely on `customAttribute(AttachmentAttribute(...))` and `customAttribute(LinkAttribute(...))`
// markers that cannot live inside an AttributedString. Every other run carries standard
// AttributedString attributes (foregroundColor, font, presentationIntent, syntax-highlight
// theme tokens, etc.) which Text(_ attributedString:) preserves natively.
//
// Building one Text per run and then `Text("\(prev)\(next)")`-reducing them into a single
// value produces a LocalizedTextStorage tree whose depth equals the run count. SwiftUI
// resolves that tree recursively at layout time, so a code block with thousands of Prism
// tokens (or any AttributedString with thousands of runs) blows the main-thread stack at
// resolve time — the "Thread stack size exceeded due to excessive recursion" crash.
//
// Instead, consecutive plain runs are coalesced into a single Text(_ attributedString:)
// and concatenated with the `+` operator only across attachment / link boundaries. The
// resulting Text-node count is bounded by `attachments + links + 1` rather than the run
// count, and the concatenation uses ConcatenatedTextStorage instead of LocalizedTextStorage,
// which avoids the localization-machinery walk entirely.
//
// The final `+`-merge is balanced (pairwise) so the ConcatenatedTextStorage tree is
// O(log N) deep, not O(N). A left-fold reduce would re-introduce the same crash class
// in a different guise for content with thousands of attachments / links.

extension TextFragment {
  @MainActor @Observable final class TextBuilder {
    var text: Text

    @ObservationIgnored private let content: Content
    @ObservationIgnored private let cache: NSCache<KeyBox<[AttachmentKey: CGSize]>, Box<Text>>

    init(_ content: Content, environment: TextEnvironmentValues) {
      let attachmentSizes = content.attachmentSizes(for: .unspecified, in: environment)

      self.text = Text(
        attributedString: content,
        attachmentSizes: attachmentSizes,
        in: environment
      )
      self.content = content
      self.cache = NSCache()
      self.cache.countLimit = 10

      self.cache.setObject(Box(self.text), forKey: KeyBox(attachmentSizes))
    }

    func sizeChanged(_ size: CGSize, environment: TextEnvironmentValues) {
      let attachmentSizes = content.attachmentSizes(for: .init(size), in: environment)
      let cacheKey = KeyBox(attachmentSizes)

      if let text = cache.object(forKey: cacheKey) {
        self.text = text.wrappedValue
      } else {
        let text = Text(
          attributedString: content,
          attachmentSizes: attachmentSizes,
          in: environment
        )
        cache.setObject(Box(text), forKey: cacheKey)

        self.text = text
      }
    }
  }
}

extension Text {
  fileprivate init(
    attributedString: some AttributedStringProtocol,
    attachmentSizes: [AttachmentKey: CGSize],
    in environment: TextEnvironmentValues
  ) {
    var pieces: [Text] = []
    var pending = AttributedString()

    func flushPending() {
      guard !pending.runs.isEmpty else { return }
      pieces.append(Text(pending))
      pending = AttributedString()
    }

    for run in attributedString.runs {
      let attachment = run.textual.attachment
      let link = run.link

      // Plain runs (no attachment, no link) carry only AttributedString attributes,
      // so they round-trip cleanly through Text(_ attributedString:). Coalesce them
      // into `pending` and only flush at attachment / link boundaries. The 99% case
      // (every Prism token in a code block, every styled span in prose) lands here
      // and never builds a runEnvironment or a separate Text node.
      if attachment == nil, link == nil {
        pending.append(AttributedString(attributedString[run.range]))
        continue
      }

      flushPending()

      var runEnvironment = environment
      runEnvironment.font = run.font ?? environment.font

      var text: Text
      if let attachment,
        let size = attachmentSizes[AttachmentKey(attachment: attachment, font: runEnvironment.font)]
      {
        text = Text(placeholderSize: size)
          .baselineOffset(attachment.baselineOffset(in: runEnvironment))
          .customAttribute(
            AttachmentAttribute(
              attachment,
              presentationIntent: run.presentationIntent
            )
          )
      } else {
        text = Text(AttributedString(attributedString[run.range]))
      }

      if let link {
        text = text.customAttribute(LinkAttribute(link))
      }

      pieces.append(text)
    }

    flushPending()

    self = Text.balancedConcatenation(of: pieces)
  }

  /// Pairwise merge of `pieces` using `+`, producing a `ConcatenatedTextStorage`
  /// tree of O(log N) depth instead of the O(N) depth a left-fold would yield.
  /// `+`-resolve still recurses, so a balanced tree is the difference between
  /// safely rendering thousands of inline pieces and overflowing the stack at
  /// layout time. The construction cost stays O(N).
  ///
  /// Internal (rather than fileprivate) so unit tests can exercise the helper
  /// directly without going through full `TextBuilder` construction.
  static func balancedConcatenation(of pieces: [Text]) -> Text {
    guard !pieces.isEmpty else { return Text(verbatim: "") }
    var level = pieces
    while level.count > 1 {
      var next: [Text] = []
      next.reserveCapacity((level.count + 1) / 2)
      var index = 0
      while index + 1 < level.count {
        next.append(level[index] + level[index + 1])
        index += 2
      }
      if index < level.count {
        next.append(level[index])
      }
      level = next
    }
    return level[0]
  }

  private init(placeholderSize size: CGSize) {
    self.init(SwiftUI.Image(size: size) { _ in })
  }
}

extension AttributedStringProtocol {
  fileprivate func attachmentSizes(
    for proposal: ProposedViewSize, in environment: TextEnvironmentValues
  ) -> [AttachmentKey: CGSize] {
    Dictionary(
      self.runs.compactMap { run in
        guard let attachment = run.textual.attachment else {
          return nil
        }
        var environment = environment
        environment.font = run.font ?? environment.font
        return (
          AttachmentKey(
            attachment: attachment,
            font: environment.font
          ),
          attachment.sizeThatFits(proposal, in: environment)
        )
      },
      uniquingKeysWith: { existing, _ in existing }
    )
  }
}

private struct AttachmentKey: Hashable {
  let attachment: AnyAttachment
  let font: Font?
}
