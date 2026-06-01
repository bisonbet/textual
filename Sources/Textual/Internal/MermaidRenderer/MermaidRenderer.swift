import Foundation
import os
import SwiftUI

#if canImport(WebKit)
  import WebKit
#endif

// MARK: - Overview
//
// MermaidRenderer uses a hidden WKWebView to render Mermaid diagram source into bitmap images.
// The bundled mermaid.min.js runs entirely offline inside a WebView, producing SVG which is then
// captured via WKWebView.takeSnapshot. Results are cached keyed by (source, width, theme).
//
// The renderer is @MainActor because WKWebView requires main-thread access. Callers interact
// through the async `render(source:width:theme:)` method.

struct MermaidDiagram: Sendable {
  let cgImage: CGImage
  let size: CGSize
}

#if canImport(WebKit)
  @MainActor
  final class MermaidRenderer: NSObject, WKNavigationDelegate {
    static let shared = MermaidRenderer()

    private let logger = Logger(category: .mermaidRenderer)
    private let cache = NSCache<NSString, Box<MermaidDiagram>>()
    private var webView: WKWebView?
    private var isReady = false
    private var readyContinuations: [CheckedContinuation<Void, Never>] = []
    private var renderQueue: [CheckedContinuation<Void, Never>] = []
    private var isRendering = false

    private override init() {
      super.init()
    }

    private func acquireRenderLock() async {
      if !isRendering {
        isRendering = true
        return
      }
      await withCheckedContinuation { continuation in
        renderQueue.append(continuation)
      }
    }

    private func releaseRenderLock() {
      if let next = renderQueue.first {
        renderQueue.removeFirst()
        next.resume()
      } else {
        isRendering = false
      }
    }

    func render(
      source: String,
      width: CGFloat,
      theme: String = "default"
    ) async -> MermaidDiagram? {
      let cacheKeyString = "\(source)|\(Int(width))|\(theme)" as NSString
      if let cached = cache.object(forKey: cacheKeyString) {
        return cached.wrappedValue
      }

      await acquireRenderLock()
      defer { releaseRenderLock() }

      // Check cache again after acquiring lock (another task may have rendered it)
      if let cached = cache.object(forKey: cacheKeyString) {
        return cached.wrappedValue
      }

      await ensureReady(theme: theme)

      guard let webView, isReady else {
        logger.error("MermaidRenderer: WebView not available.")
        return nil
      }

      let js = """
        const result = await renderDiagram(source, containerId);
        return result;
        """

      do {
        let diagramId = "d\(UUID().uuidString.prefix(8).lowercased())"

        guard
          let resultString = try await webView.callAsyncJavaScript(
            js,
            arguments: ["source": source, "containerId": diagramId],
            contentWorld: .page
          ) as? String,
          let resultData = resultString.data(using: .utf8),
          let result = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any]
        else {
          logger.error("MermaidRenderer: Failed to parse render result.")
          return nil
        }

        if let error = result["error"] as? String {
          logger.error("MermaidRenderer: JS error: \(error)")
          return nil
        }

        guard let diagramWidth = result["width"] as? Double,
          let diagramHeight = result["height"] as? Double,
          diagramWidth > 0, diagramHeight > 0
        else {
          logger.error("MermaidRenderer: Missing dimensions in result.")
          return nil
        }

        let diagramSize = CGSize(width: diagramWidth, height: diagramHeight)

        // Resize the webview to match the diagram for a clean snapshot
        webView.frame = CGRect(origin: .zero, size: diagramSize)

        // Small delay for layout to settle
        try? await Task.sleep(for: .milliseconds(100))

        let config = WKSnapshotConfiguration()
        config.snapshotWidth = NSNumber(value: diagramWidth)

        let snapshotImage = try await webView.takeSnapshot(configuration: config)

        #if canImport(UIKit)
          guard let cgImage = snapshotImage.cgImage else {
            logger.error("MermaidRenderer: Failed to get CGImage from snapshot.")
            return nil
          }
        #elseif canImport(AppKit)
          guard
            let cgImage = snapshotImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
          else {
            logger.error("MermaidRenderer: Failed to get CGImage from snapshot.")
            return nil
          }
        #endif

        let diagram = MermaidDiagram(cgImage: cgImage, size: diagramSize)
        // Bitmap cost in bytes so NSCache can evict by actual memory weight.
        let cost = cgImage.bytesPerRow * cgImage.height
        cache.setObject(Box(diagram), forKey: cacheKeyString, cost: cost)
        return diagram
      } catch {
        logger.error("MermaidRenderer: \(error.localizedDescription)")
        return nil
      }
    }

    // MARK: - Setup

    private func ensureReady(theme: String) async {
      if isReady {
        await applyTheme(theme)
        return
      }

      if webView != nil {
        await withCheckedContinuation { continuation in
          readyContinuations.append(continuation)
        }
        await applyTheme(theme)
        return
      }

      guard let htmlString = loadHTMLTemplate() else {
        logger.error("MermaidRenderer: Failed to load HTML template.")
        return
      }

      let config = WKWebViewConfiguration()
      config.suppressesIncrementalRendering = true

      let wv = WKWebView(
        frame: CGRect(origin: .zero, size: CGSize(width: 800, height: 600)),
        configuration: config
      )
      wv.navigationDelegate = self
      #if canImport(UIKit)
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.isScrollEnabled = false
      #elseif canImport(AppKit)
        wv.setValue(false, forKey: "drawsBackground")
      #endif

      self.webView = wv
      wv.loadHTMLString(htmlString, baseURL: nil)

      // Wait for navigation delegate callback
      await withCheckedContinuation { continuation in
        readyContinuations.append(continuation)
      }

      await applyTheme(theme)
    }

    // Invokes `initMermaid` in the page via callAsyncJavaScript so the theme
    // string travels as an argument rather than being interpolated into JS
    // source. Today the only callers pass "default" or "dark", but the
    // argument-based path closes the door on injection if that ever changes.
    private func applyTheme(_ theme: String) async {
      guard let webView else { return }
      _ = try? await webView.callAsyncJavaScript(
        "initMermaid(theme, darkMode);",
        arguments: ["theme": theme, "darkMode": theme == "dark"],
        contentWorld: .page
      )
    }

    // MARK: - WKNavigationDelegate

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      Task { @MainActor in
        isReady = true
        for continuation in readyContinuations {
          continuation.resume()
        }
        readyContinuations.removeAll()
      }
    }

    nonisolated func webView(
      _ webView: WKWebView,
      didFail navigation: WKNavigation!,
      withError error: Error
    ) {
      Task { @MainActor in
        logger.error("MermaidRenderer: Navigation failed: \(error.localizedDescription)")
        isReady = false
        // Drop the failed WebView so the next ensureReady call can build a
        // fresh one. Without this, a transient init failure would leave the
        // renderer permanently stuck on a never-firing navigation callback.
        self.webView = nil
        for continuation in readyContinuations {
          continuation.resume()
        }
        readyContinuations.removeAll()
      }
    }

    // MARK: - Template

    private func loadHTMLTemplate() -> String? {
      guard
        let templateURL = Bundle.textual?.url(
          forResource: "mermaid-template",
          withExtension: "html"
        ),
        var template = try? String(contentsOf: templateURL, encoding: .utf8),
        let jsURL = Bundle.textual?.url(
          forResource: "mermaid.min",
          withExtension: "js"
        ),
        let jsContent = try? String(contentsOf: jsURL, encoding: .utf8)
      else {
        return nil
      }

      template = template.replacingOccurrences(
        of: "MERMAID_JS_PLACEHOLDER",
        with: jsContent
      )

      return template
    }
  }
#else
  @MainActor
  final class MermaidRenderer {
    static let shared = MermaidRenderer()
    private let logger = Logger(category: .mermaidRenderer)

    private init() {}

    func render(
      source: String,
      width: CGFloat,
      theme: String = "default"
    ) async -> MermaidDiagram? {
      logger.error("MermaidRenderer: WebKit is not available on this platform.")
      return nil
    }
  }
#endif

extension Logger.Textual.Category {
  static let mermaidRenderer = Self(rawValue: "mermaidRenderer")
}
