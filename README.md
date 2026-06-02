# Arzu Code 🤖

> An agentic AI coding assistant for macOS — point it at a folder, describe what you want, and let it read, reason, and edit your code.

![Flutter](https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-0175C2?logo=dart&logoColor=white)
![Gemini](https://img.shields.io/badge/Gemini-Vertex_AI-8E75B2?logo=googlegemini&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-macOS-000000?logo=apple&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green)

Arzu Code is a native desktop companion in the spirit of Cursor and Claude Code. It keeps your whole project in context, talks to you in chat, and acts through real tools — reading files, writing edits, turning a screenshot into UI, and running terminals — all powered by **Gemini through Google Vertex AI**.

## ✨ Highlights
- 💬 **Chat-driven agent** with tool access to your file system
- 📂 **Built-in file explorer** to browse and open any project
- 🖥️ **Embedded terminals** for running commands without leaving the app
- 🖼️ **Vision** — drag in a screenshot and get matching code
- 🎨 **Image generation** built into the workflow
- 🌙 Dark, IDE-inspired layout with Markdown + syntax highlighting

## 🛠️ Tech Stack
- **Language:** Dart
- **Framework:** Flutter (macOS desktop)
- **State:** Riverpod
- **AI:** `firebase_ai`, `google_generative_ai`, Vertex AI (`googleapis_auth`)
- **UI:** Google Fonts, Lucide icons, Flutter Markdown
- **System:** file_picker, desktop_drop, pasteboard, url_launcher

## 📁 Project Structure
```
lib/
├── models/      # chat, message, project, tool-call models
├── providers/   # Riverpod state (chat, agent, settings, file tree)
├── services/    # Gemini/Vertex client, file system, agent tools, auth
├── theme/       # dark IDE theme
├── ui/          # chat panel, file explorer, terminal, editor
└── main.dart
macos/           # native desktop runner
```

## 🚀 Getting Started
```bash
flutter pub get
flutter run -d macos              # development
flutter build macos --release     # build the .app
```

Vertex AI access needs a Google Cloud **service account** with the Vertex AI API enabled. Place your own `service_account.json` in the project root (it is git-ignored and never committed).

## 🔗 Related
The Electron/TypeScript sibling of this project lives at [qalam](https://github.com/arzucoder/qalam).

---

<div align="center">

**Powered by [ARZUCODER](https://arzucoder.uz)** ⚡

</div>
