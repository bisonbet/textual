#if TEXTUAL_ENABLE_TEXT_SELECTION
  import SwiftUI
  import Testing

  @testable import Textual

  // Tests for the .textual.interactiveRegion() modifier (issue #40).
  //
  // The modifier marks a view as an interactive control that must receive pointer
  // events even when a text-selection overlay covers the whole StructuredText.
  // Internally it registers the view's frame in OverflowFrameKey so the overlay's
  // hitTest passes through for that specific area.
  //
  // Design constraint: the exclusion must be limited to the interactive element
  // itself.  Registering a large region (e.g. the whole CodeBlockStyle body) would
  // silently prevent text selection in that area — the exact mistake this test suite
  // guards against.
  //
  // BEFORE FIX: this file does not compile — .textual.interactiveRegion() does not exist.
  // AFTER  FIX: file compiles; all tests pass.

  #if canImport(AppKit)
    import AppKit

    @Suite("textual.interactiveRegion modifier")
    struct InteractiveRegionModifierTests {

      // Renders `view` inside a named textContainer coordinate space and returns
      // the OverflowFrameKey frames propagated by the view tree.
      @MainActor
      private func captureOverflowFrames<V: View>(
        from view: V,
        canvasSize: CGSize = CGSize(width: 200, height: 100)
      ) -> [CGRect] {
        var capturedFrames: [CGRect] = []
        let observed = view
          .coordinateSpace(.textContainer)
          .onPreferenceChange(OverflowFrameKey.self) { capturedFrames = $0 }
          .frame(width: canvasSize.width, height: canvasSize.height)

        let hosting = NSHostingView(rootView: observed)
        hosting.frame = CGRect(origin: .zero, size: canvasSize)
        hosting.layout()
        hosting.layout()  // second pass to stabilize GeometryReader
        return capturedFrames
      }

      // A view with the modifier applied must register its frame.
      @Test @MainActor
      func modifier_registersFrame() {
        let frames = captureOverflowFrames(
          from: Color.red
            .frame(width: 40, height: 20)
            .textual.interactiveRegion()
        )
        #expect(!frames.isEmpty)
      }

      // The registered frame must be approximately the size of the decorated view,
      // not the whole canvas.  This guards against a naïve implementation that
      // registers the surrounding container instead of just the control.
      @Test @MainActor
      func modifier_registersOnlyItsOwnFrame() {
        let canvasWidth: CGFloat = 200
        let canvasHeight: CGFloat = 100
        let controlWidth: CGFloat = 40
        let controlHeight: CGFloat = 20

        let frames = captureOverflowFrames(
          from: Color.red
            .frame(width: controlWidth, height: controlHeight)
            .textual.interactiveRegion(),
          canvasSize: CGSize(width: canvasWidth, height: canvasHeight)
        )

        let totalExcludedArea = frames.reduce(CGFloat(0)) { $0 + $1.width * $1.height }
        let canvasArea = canvasWidth * canvasHeight

        // The control is 40×20 = 800 pt²; the canvas is 200×100 = 20 000 pt².
        // Excluded area must be well below the full canvas.
        #expect(
          totalExcludedArea < canvasArea * 0.15,
          "Excluded area \(totalExcludedArea) pt² should be much smaller than the canvas \(canvasArea) pt²"
        )
      }

      // Views that do NOT carry the modifier must not appear in the exclusion rects.
      // This verifies that the modifier does not accidentally "infect" sibling views.
      @Test @MainActor
      func modifier_doesNotExcludeAdjacentViews() {
        let frames = captureOverflowFrames(
          from: HStack(spacing: 0) {
            // Leading and trailing sibling views — no modifier applied.
            Color.blue.frame(width: 80, height: 50)
            // Only this view carries the modifier.
            Color.red
              .frame(width: 40, height: 20)
              .textual.interactiveRegion()
            Color.green.frame(width: 80, height: 50)
          }
        )

        // Exactly one exclusion frame should be registered.
        #expect(frames.count == 1)
      }
    }
  #endif  // canImport(AppKit)
#endif  // TEXTUAL_ENABLE_TEXT_SELECTION
