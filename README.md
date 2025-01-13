# Snip - A modern web element inspector

Snip is a modern web element inspector that makes it easy to clip elements of a web page and examine their underlying content, code, and important styles. Originally built with AI-assisted development in mind, Snip helps developers and content creators quickly grab context from webpages by providing clean, structured access to both text content and HTML markup.

While designed to streamline the process of gathering web content for AI interactions, Snip is versatile enough for any use case where you need to analyze or extract web elements - whether you're developing, designing, or researching.

## Features

- 🔍 Interactive element inspection with visual highlighting
- 📝 Clean text extraction with preserved formatting
- 🔬 Detailed HTML inspection
- 🌐 Built-in web browser with navigation controls
- 💻 Native macOS app with modern SwiftUI interface

## Requirements

- macOS 12.0 or later
- Xcode 14.0 or later

## Installation

1. Clone the repository
2. Open `Snip.xcodeproj` in Xcode
3. Build and run the project

## Usage

1. Launch the app and navigate to any webpage
2. Click the scissors icon to enter inspection mode
3. Hover over elements to highlight them
4. Click on an element to analyze its:
   - Preview image
   - Clean text content
   - Element metadata (tag, class, XPath, URL)
   - DOM context (parent, children, siblings)
   - Computed styles
   - Accessibility information

5. Copy content using:
   - "Copy All" button at the top to copy everything
   - Individual copy buttons for Preview, Content, and Info sections
   - Content is copied in a structured format with images appearing first

## Development

The app is built using:
- SwiftUI for the user interface
- WebKit for web content rendering
- Combine for reactive programming

## License

[MIT License](LICENSE)
