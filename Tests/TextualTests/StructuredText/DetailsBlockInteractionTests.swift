#if TEXTUAL_ENABLE_TEXT_SELECTION && canImport(AppKit)
  import AppKit
  import SwiftUI
  import Testing

  @testable import Textual

  // Tests that verify DetailsBlock only excludes its toggle button from text selection
  // hit-testing — not the entire block.
  //
  // The text-selection overlay (NSTextInteractionView) skips hit-testing for any rect
  // registered in OverflowFrameKey, passing pointer events through to the underlying
  // SwiftUI view instead.  Registering the *whole* DetailsBlock frame (the current
  // naïve approach) achieves a clickable toggle but silently prevents the summary
  // InlineText from being selected.
  //
  // The correct fix is a custom toggle layout that only registers the small toggle
  // button frame, leaving the summary text in normal selection territory.
  //
  // BEFORE FIX: both tests below fail — the entire block frame is excluded.
  // AFTER  FIX: both tests pass — only the narrow toggle area is excluded.
  @Suite("DetailsBlock interaction")
  struct DetailsBlockInteractionTests {

    // Renders a DetailsBlock in isolation and returns the OverflowFrameKey frames
    // that it propagates to its ancestor.  Two layout passes are needed because
    // GeometryReader requires a second pass to report stable geometry.
    @MainActor
    private func captureExclusionFrames(
      blockWidth: CGFloat = 300,
      blockHeight: CGFloat = 60
    ) -> [CGRect] {
      var capturedFrames: [CGRect] = []

      let content = AttributedString("Body content for testing.")
      let contentSubstr = content[content.startIndex..<content.endIndex]
      let block = StructuredText.DetailsBlock(contentSubstr, summary: "Click to expand")

      let view = block
        .frame(width: blockWidth, height: blockHeight)
        .coordinateSpace(.textContainer)
        .onPreferenceChange(OverflowFrameKey.self) { capturedFrames = $0 }

      let hosting = NSHostingView(rootView: view)
      hosting.frame = CGRect(x: 0, y: 0, width: blockWidth, height: blockHeight)
      hosting.layout()
      hosting.layout()

      return capturedFrames
    }

    // The total excluded area should be a small fraction of the block — roughly the
    // size of a disclosure triangle (~20 × 20 pt), not the entire 300 × 60 pt block.
    @Test @MainActor
    func detailsBlock_exclusionZone_isLimitedToToggleArea() {
      let blockWidth: CGFloat = 300
      let blockHeight: CGFloat = 60
      let frames = captureExclusionFrames(blockWidth: blockWidth, blockHeight: blockHeight)

      #expect(!frames.isEmpty, "DetailsBlock must register at least one exclusion frame for the toggle")

      let totalExcludedArea = frames.reduce(CGFloat(0)) { $0 + $1.width * $1.height }
      let totalBlockArea = blockWidth * blockHeight

      // A disclosure toggle is ≈20×20 pt (400 pt²).  The threshold of 25 % of the
      // total block area (4 500 pt²) is generous but still far below the full block.
      //
      // BEFORE FIX: totalExcludedArea ≈ 18 000 pt² → assertion fails.
      // AFTER  FIX: totalExcludedArea ≈ 400 pt²    → assertion passes.
      #expect(
        totalExcludedArea < totalBlockArea * 0.25,
        "Exclusion zone covers \(totalExcludedArea) pt² but should be ≤ \(totalBlockArea * 0.25) pt²"
      )
    }

    // A point inside the summary-text area (well clear of the toggle arrow) must
    // NOT be in any exclusion rect, so the parent selection overlay can accept
    // drag-to-select gestures there.
    @Test @MainActor
    func detailsBlock_summaryTextArea_isNotExcluded() {
      let frames = captureExclusionFrames()

      // The toggle arrow sits near the leading edge of the row (x ≈ 0–20 pt).
      // x = 60 is comfortably inside the summary InlineText area.
      let summaryTextPoint = CGPoint(x: 60, y: 15)
      let isExcluded = frames.contains { $0.contains(summaryTextPoint) }

      // BEFORE FIX: the whole block frame includes (60, 15) → isExcluded == true → fails.
      // AFTER  FIX: only the toggle frame is registered; (60, 15) is outside → passes.
      #expect(!isExcluded, "Summary text at \(summaryTextPoint) should be selectable, not in an exclusion zone")
    }
  }
#endif
