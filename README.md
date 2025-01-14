# Snip – A modern web content clipper.

**Snip** is a tool I built for myself to quickly clip text, HTML, and key styles from any webpage. It was originally meant to make AI-assisted tasks easier, but I found it useful for all sorts of web content analysis—so I’m sharing it in case you might find it helpful, too.



## Features

- **Interactive Highlighting** – Hover over elements to see exactly what you’re inspecting  
- **Clean Text Extraction** – Copy only the text, keeping basic formatting intact  
- **HTML Inspection** – Peek at the underlying markup  
- **Built-In Browser** – Navigate webpages directly within Snip  
- **SwiftUI Interface** – A native macOS app that feels right at home

## Requirements

- macOS **12.0** or later  
- Xcode **14.0** or later  

## Installation

1. **Clone** this repository  
2. **Open** `Snip.xcodeproj` in Xcode  
3. **Build and run** the project  

## Usage

1. **Launch Snip** and load any webpage  
2. **Activate Inspection Mode** by clicking the scissors icon  
3. **Hover** over elements to highlight them  
4. **Click** on an element to see:
   - **Preview Image** (shortcut: `1`)  
   - **Element Metadata** (ID, tag, class, XPath, URL) (shortcut: `2`)  
   - **Clean Text Content** (shortcut: `3`)  
5. **Use Keyboard Shortcuts**:
   - Press `c` to toggle clip mode  
   - Press `1` to copy the preview image  
   - Press `2` to copy element info  
   - Press `3` to copy text content  
6. **Copy Content** using the individual copy buttons for each section—everything comes out nicely structured

## Development

Snip is built with a few core technologies:
- **SwiftUI** – for a clean, native user interface  
- **WebKit** – for rendering web pages  
- **Combine** – for reactive updates and data flow  

## License

This project is distributed under the [MIT License](LICENSE). I hope you find it as useful as I do!
