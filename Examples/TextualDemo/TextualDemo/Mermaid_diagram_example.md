# Architecture Example — Mermaid Diagrams

A shareable example showing Mermaid diagram types (flowchart, sequence) for system architecture documentation.

---

## High-Level Overview

```mermaid
flowchart TB
    subgraph Clients["Clients"]
        App["Native Desktop App<br/>Swift/SwiftUI + Rust"]
        Web["Marketing Website<br/>Astro + CMS"]
    end

    subgraph Edge["Edge"]
        Gateway["API Gateway<br/>:8xxx"]
        BFF["BFF<br/>/api/* proxy"]
    end

    subgraph Workers["Workers"]
        Auth["auth :8xxx<br/>DB · magic link · activate"]
        Billing["billing :8xxx<br/>DB · payments · webhooks"]
        Session["session :8xxx<br/>cookies · CSRF"]
        Content["content :8xxx<br/>CMS → release JSON"]
        Notifications["notifications :8xxx<br/>CMS → inbox"]
        Assets["assets :8xxx<br/>object storage proxy"]
        Emails["emails :8xxx<br/>email provider · templates"]
    end

    subgraph Data["Data & External"]
        DB[(DB<br/>shared schema)]
        Storage[(Object Storage)]
        CMS[(CMS)]
        Payments[Payment Provider]
        EmailProvider[Email Provider]
    end

    App --> Gateway
    Web --> BFF
    BFF --> Gateway
    Gateway --> Auth
    Gateway --> Billing
    Gateway --> Session
    Gateway --> Content
    Gateway --> Notifications
    Gateway --> Assets
    Gateway --> Emails

    Auth --> DB
    Billing --> DB
    Billing --> Payments
    Emails --> EmailProvider
    Content --> CMS
    Notifications --> CMS
    Assets --> Storage
    Emails --> CMS
```

---

## Auth & Licensing Flow

```mermaid
sequenceDiagram
    participant U as User
    participant App as Desktop App
    participant Web as Web
    participant Session as session
    participant Auth as auth
    participant DB as DB

    Note over U,DB: Magic link flow
    U->>Web: Request magic link
    Web->>Auth: POST /v1/auth/send-magic-link
    Auth->>DB: Store code
    Auth->>Auth: Send email
    U->>Web: Click link
    Web->>Auth: POST /v1/auth/exchange
    Auth->>Session: Create session cookie
    Web->>U: Logged in

    Note over U,DB: App-to-web handoff
    U->>App: View Account
    App->>Auth: POST /v1/auth/app-sso/start
    Auth-->>App: handoff_token, intent_id
    App->>Web: Open /account/sso#...
    Web->>Session: POST /v1/session/exchange
    Web->>U: Account page

    Note over U,DB: Activation
    U->>App: Activate
    App->>Auth: POST /v1/activate (Bearer)
    Auth->>DB: Validate + issue lease
    Auth-->>App: lease_token, auth tokens
```

---

## Backend Workers Detail

```mermaid
flowchart LR
    subgraph ControlPlane["Control-plane"]
        direction TB
        A[auth]
        B[billing]
        S[session]
        C[content]
        N[notifications]
    end

    subgraph DataPlane["Data-plane"]
        AS[assets]
        E[emails]
    end

    subgraph Bindings["Bindings"]
        DB[(DB)]
        R2[(Object Storage)]
        KV[KV]
        DO[DO]
    end

    A --> DB
    A --> KV
    A --> DO
    B --> DB
    B --> KV
    S --> KV
    C --> CMS[(CMS)]
    N --> CMS
    AS --> R2
    E --> CMS
    E --> Email[Email Provider]
```

---

## Local Development Topology

```mermaid
flowchart TB
    subgraph Dev["Local dev"]
        direction TB
        W1["auth :8xxx"]
        W2["billing :8xxx"]
        W3["content :8xxx"]
        W4["session :8xxx"]
        W5["api gateway :8xxx"]
    end

    subgraph WebDev["Web server"]
        BFF["BFF :4xxx<br/>proxies /api/* → localhost"]
    end

    subgraph CMS["CMS"]
        Studio["CMS Studio :3xxx"]
    end

    App["Desktop App<br/>Debug → localhost"]
    Browser["Browser"]
    SharedDB[(".wrangler/state<br/>shared DB emulation")]

    App --> W5
    Browser --> BFF
    BFF --> W5
    W5 --> W1
    W5 --> W2
    W5 --> W3
    W5 --> W4
    W1 --> SharedDB
    W2 --> SharedDB
```

---

## Infrastructure & Secrets

```mermaid
flowchart TB
    subgraph Source["Secrets source"]
        Vault[Secrets Manager]
        Config[Config resolver]
    end

    subgraph Deploy["Deploy-time"]
        IaC[IaC<br/>DB, storage, zone]
        CLI[CLI<br/>workers, KV, secrets]
    end

    subgraph Runtime["Runtime"]
        Workers[Workers]
        DB[(DB)]
        Storage[(Storage)]
        KV[(KV)]
    end

    Vault --> Config
    Config --> IaC
    Config --> CLI
    IaC --> DB
    IaC --> Storage
    CLI --> Workers
    CLI --> KV
```

---

## Repo Layout (example)

| Area | Path | Purpose |
|------|------|---------|
| App | `app/` | Native desktop app, optional backend lib |
| Web | `web/` | Marketing site, CMS studio |
| Backend | `backend/` | Workers, IaC, schema |
| Docs | `docs/` | Runbooks, architecture |
