# Headshot Generator

A native macOS app, plus a website version, that turns an everyday photo into a clean, professional-looking headshot and a set of stylized avatars. Everything runs on your Mac with Apple's Vision and Core Image frameworks: no cloud, no API keys, and your photos never leave the machine.

```mermaid
flowchart LR
    A[Your photo] --> B["Vision: find the face<br/>and outline the person"]
    B --> C["Light and colour:<br/>auto-enhance, exposure,<br/>contrast, warmth"]
    C --> D["Skin smoothing<br/>(person only)"]
    D --> E["New background:<br/>blur, solid or gradient"]
    E --> F["Crop around the face<br/>1:1, 4:5 or uncropped"]
    F --> G[Headshot PNG / JPEG]
    F --> H["Avatars: Cartoon, Pop Art,<br/>Sketch, Duotone, Halftone, Pixel"]
```

**[Instructions →](docs/INSTRUCTIONS.md)** · [System design](docs/SYSTEM-DESIGN.md) · [File structure](docs/FILE-STRUCTURE.md) · [Try it in your browser](https://amalmehta.github.io/headshot_generator/)
