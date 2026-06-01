import SwiftUI

extension StructuredText {
  struct MermaidCodeBlock: View {
    @Environment(\.codeBlockStyle) private var codeBlockStyle
    @Environment(\.highlighterTheme) private var highlighterTheme
    @Environment(\.colorScheme) private var colorScheme
    @State private var diagram: MermaidDiagram?

    private let source: String
    private let content: AttributedSubstring
    private let indentationLevel: Int

    init(_ content: AttributedSubstring) {
      self.content = content
      self.source = String(content.characters[...])
        .trimmingCharacters(in: .whitespacesAndNewlines)
      self.indentationLevel = content.presentationIntent?.indentationLevel ?? 0
    }

    var body: some View {
      let configuration = CodeBlockStyleConfiguration(
        label: .init(diagramView),
        indentationLevel: indentationLevel,
        languageHint: "mermaid",
        codeBlock: .init(content),
        highlighterTheme: highlighterTheme
      )
      let resolvedStyle = codeBlockStyle.resolve(configuration: configuration)

      AnyView(resolvedStyle)
        .id(source)
        .task(id: source) {
          let theme = colorScheme == .dark ? "dark" : "default"
          diagram = await MermaidRenderer.shared.render(
            source: source,
            width: 800,
            theme: theme
          )
        }
    }

    @ViewBuilder
    private var diagramView: some View {
      if let diagram {
        SwiftUI.Image(diagram.cgImage, scale: 2, label: Text("Mermaid diagram"))
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(maxWidth: diagram.size.width / 1.5, maxHeight: diagram.size.height / 1.5)
          .frame(maxWidth: .infinity)
          .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
      } else {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .fill(highlighterTheme.backgroundColor)
          .overlay {
            ProgressView()
          }
          .frame(height: 200)
      }
    }
  }
}
