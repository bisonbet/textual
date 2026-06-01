#if TEXTUAL_ENABLE_TEXT_SELECTION && canImport(AppKit)
  import AppKit
  import SwiftUI
  import Testing

  @testable import Textual

  // Regression tests for NSTextInteractionView.hitTest exclusion-rect logic.
  //
  // These verify the core mechanism that both DetailsBlock and the
  // .textual.interactiveRegion() modifier rely on: a point that falls inside
  // any exclusion rect must pass through the overlay (hitTest returns nil),
  // while points outside are handled by the overlay for text selection.
  @Suite("NSTextInteractionView")
  struct NSTextInteractionViewTests {

    // NSTextInteractionView.isFlipped == true (y increases downward). The production
  // container is NSHostingView, which is also flipped. Using an unflipped NSView
  // as the container would cause convert(point, from:) to flip y before checking
  // exclusionRects, making points appear at unexpected coordinates. This subclass
  // matches the production environment.
  private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
  }

  @MainActor
    private func makeView(exclusionRects: [CGRect]) throws -> NSTextInteractionView {
      // Place the interaction view inside a flipped container to match the NSHostingView
      // environment used in production.
      let container = FlippedView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
      let model = try TextSelectionModel(fixtureName: "two-paragraphs-bidi")
      let view = NSTextInteractionView(
        model: model,
        exclusionRects: exclusionRects,
        openURL: OpenURLAction { _ in .handled }
      )
      view.frame = CGRect(x: 0, y: 0, width: 400, height: 400)
      container.addSubview(view)
      return view
    }

    @Test @MainActor
    func pointOutsideExclusionRect_isHandledByOverlay() throws {
      let view = try makeView(exclusionRects: [CGRect(x: 50, y: 50, width: 100, height: 100)])
      #expect(view.hitTest(CGPoint(x: 300, y: 300)) === view)
    }

    @Test @MainActor
    func pointInsideExclusionRect_passesThrough() throws {
      let view = try makeView(exclusionRects: [CGRect(x: 50, y: 50, width: 100, height: 100)])
      #expect(view.hitTest(CGPoint(x: 100, y: 100)) == nil)
    }

    @Test @MainActor
    func pointOnExclusionRectOrigin_passesThrough() throws {
      // CGRect.contains treats the origin as inside the rect.
      let view = try makeView(exclusionRects: [CGRect(x: 50, y: 50, width: 100, height: 100)])
      #expect(view.hitTest(CGPoint(x: 50, y: 50)) == nil)
    }

    @Test @MainActor
    func emptyExclusionRects_allPointsHandledByOverlay() throws {
      let view = try makeView(exclusionRects: [])
      #expect(view.hitTest(CGPoint(x: 100, y: 100)) === view)
    }

    @Test @MainActor
    func multipleExclusionRects_pointInAnyRectPassesThrough() throws {
      let rects = [
        CGRect(x: 10, y: 10, width: 50, height: 50),
        CGRect(x: 200, y: 200, width: 50, height: 50),
      ]
      let view = try makeView(exclusionRects: rects)
      // Inside first rect
      #expect(view.hitTest(CGPoint(x: 30, y: 30)) == nil)
      // Inside second rect
      #expect(view.hitTest(CGPoint(x: 220, y: 220)) == nil)
      // Between the two rects
      #expect(view.hitTest(CGPoint(x: 120, y: 120)) === view)
    }
  }
#endif
