import SwiftUI
import Textual

struct MermaidDiagramDemo: View {
  var body: some View {
    Form {
      Section("Flowchart") {
        StructuredText(
          markdown: """
            ```mermaid
            flowchart TB
                subgraph Clients["Clients"]
                    App["Native Desktop App"]
                    Web["Marketing Website"]
                end

                subgraph Edge["Edge"]
                    Gateway["API Gateway"]
                    BFF["BFF"]
                end

                subgraph Workers["Workers"]
                    Auth["auth"]
                    Billing["billing"]
                    Session["session"]
                    Content["content"]
                end

                App --> Gateway
                Web --> BFF
                BFF --> Gateway
                Gateway --> Auth
                Gateway --> Billing
                Gateway --> Session
                Gateway --> Content
            ```
            """
        )
        .textual.textSelection(.enabled)
      }

      Section("Sequence Diagram") {
        StructuredText(
          markdown: """
            ```mermaid
            sequenceDiagram
                participant U as User
                participant App as Desktop App
                participant Auth as auth
                participant DB as DB

                Note over U,DB: Magic link flow
                U->>App: Request magic link
                App->>Auth: POST /v1/auth/send-magic-link
                Auth->>DB: Store code
                Auth->>Auth: Send email
                U->>App: Click link
                App->>Auth: POST /v1/auth/exchange
                Auth-->>App: session token
                App->>U: Logged in
            ```
            """
        )
        .textual.textSelection(.enabled)
      }

      Section("Simple Flowchart") {
        StructuredText(
          markdown: """
            ```mermaid
            flowchart LR
                A[Start] --> B{Decision}
                B -->|Yes| C[Do something]
                B -->|No| D[Do something else]
                C --> E[End]
                D --> E
            ```
            """
        )
        .textual.textSelection(.enabled)
      }
    }
    .formStyle(.grouped)
  }
}

#Preview {
  MermaidDiagramDemo()
}
