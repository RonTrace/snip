//
//  ContentView.swift
//  Snip
//
//  Created by Ron Kurti on 1/12/25.
//

import SwiftUI
import WebKit

class WebViewModel: ObservableObject {
    @Published var url: String = "https://www.apple.com"
    @Published var isLoading: Bool = false
    @Published var title: String = ""
    @Published var errorMessage: String?
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var selectedElement: SelectedElement?
    @Published var isClipModeActive: Bool = false {
        didSet {
            if isClipModeActive {
                enableClipMode()
            } else {
                disableClipMode()
            }
        }
    }
    
    private var webView: WKWebView?
    internal let scriptHandler = WebViewScriptHandler()
    
    init() {
        scriptHandler.onElementSelected = { [weak self] content, tagName, className, textContent, rect, restore, metadata in
            DispatchQueue.main.async {
                guard let webView = self?.webView else { return }
                
                // Create configuration for snapshot
                let config = WKSnapshotConfiguration()
                config.rect = CGRect(x: rect["x"] ?? 0,
                                   y: rect["y"] ?? 0,
                                   width: rect["width"] ?? 0,
                                   height: rect["height"] ?? 0)
                
                // Take snapshot of the element
                webView.takeSnapshot(with: config) { image, error in
                    DispatchQueue.main.async {
                        if let error = error {
                            print("Snapshot error: \(error)")
                            self?.selectedElement = SelectedElement(
                                content: content,
                                tagName: tagName,
                                className: className,
                                textContent: textContent,
                                image: nil,
                                metadata: metadata
                            )
                        } else {
                            self?.selectedElement = SelectedElement(
                                content: content,
                                tagName: tagName,
                                className: className,
                                textContent: textContent,
                                image: image,
                                metadata: metadata
                            )
                        }
                    }
                }
            }
        }
    }
    
    func setWebView(_ webView: WKWebView) {
        self.webView = webView
        loadInitialURL()
        updateNavigationState()
    }
    
    private func loadInitialURL() {
        guard let url = URL(string: self.url) else { return }
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
        webView?.load(request)
    }
    
    func updateNavigationState() {
        DispatchQueue.main.async {
            self.canGoBack = self.webView?.canGoBack ?? false
            self.canGoForward = self.webView?.canGoForward ?? false
            if let urlString = self.webView?.url?.absoluteString {
                self.url = urlString
            }
        }
    }
    
    func loadURL() {
        guard !url.isEmpty else { return }
        
        var urlString = url
        if !urlString.starts(with: "http") {
            urlString = "https://" + urlString
            DispatchQueue.main.async {
                self.url = urlString
            }
        }
        
        guard let url = URL(string: urlString) else { return }
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
        webView?.load(request)
    }
    
    func goBack() {
        webView?.goBack()
    }
    
    func goForward() {
        webView?.goForward()
    }
    
    func reload() {
        webView?.reload()
    }
    
    func enableClipMode() {
        webView?.evaluateJavaScript(WebViewScripts.highlightScript, completionHandler: nil)
    }
    
    func disableClipMode() {
        webView?.evaluateJavaScript(WebViewScripts.disableHighlightScript, completionHandler: nil)
    }
}

class WebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    var parent: WebView
    private var timeoutTimer: Timer?
    
    init(_ parent: WebView) {
        self.parent = parent
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        timeoutTimer?.invalidate()
        
        // Update URL in the address bar when a link is clicked
        if let url = navigationAction.request.url?.absoluteString {
            DispatchQueue.main.async {
                self.parent.viewModel.url = url
            }
        }
        
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.parent.viewModel.isLoading = false
                self?.parent.viewModel.errorMessage = "Request timed out. Please try again."
            }
            webView.stopLoading()
        }
        
        decisionHandler(.allow)
    }
    
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        DispatchQueue.main.async {
            self.parent.viewModel.isLoading = true
            self.parent.viewModel.errorMessage = nil
        }
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        timeoutTimer?.invalidate()
        DispatchQueue.main.async {
            self.parent.viewModel.isLoading = false
            self.parent.viewModel.title = webView.title ?? ""
            self.parent.viewModel.updateNavigationState()
            
            // Reapply clip mode if active
            if self.parent.viewModel.isClipModeActive {
                self.parent.viewModel.enableClipMode()
            }
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleError(error)
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleError(error)
    }
    
    private func handleError(_ error: Error) {
        timeoutTimer?.invalidate()
        
        let nsError = error as NSError
        DispatchQueue.main.async {
            self.parent.viewModel.isLoading = false
            
            if nsError.domain == NSURLErrorDomain {
                switch nsError.code {
                case -999: // Request cancelled
                    self.parent.viewModel.errorMessage = nil
                case -1001:
                    self.parent.viewModel.errorMessage = "The request timed out. Please try again."
                case -1003:
                    self.parent.viewModel.errorMessage = "Cannot find the specified host. Please check the URL."
                case -1009:
                    self.parent.viewModel.errorMessage = "No internet connection. Please check your network settings."
                default:
                    self.parent.viewModel.errorMessage = error.localizedDescription
                }
            } else {
                self.parent.viewModel.errorMessage = error.localizedDescription
            }
        }
    }
    
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

struct NavigationBar: View {
    @ObservedObject var viewModel: WebViewModel
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                NavigationButtons(viewModel: viewModel)
                
                URLBar(viewModel: viewModel)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct NavigationButtons: View {
    @ObservedObject var viewModel: WebViewModel
    
    var body: some View {
        HStack(spacing: 8) {
            Button(action: { viewModel.goBack() }) {
                Image(systemName: "chevron.left")
            }
            .disabled(!viewModel.canGoBack)
            
            Button(action: { viewModel.goForward() }) {
                Image(systemName: "chevron.right")
            }
            .disabled(!viewModel.canGoForward)
            
            Button(action: { viewModel.reload() }) {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(viewModel.isLoading)
        }
        .frame(width: 100, alignment: .leading)
    }
}

struct URLBar: View {
    @ObservedObject var viewModel: WebViewModel
    
    var body: some View {
        HStack(spacing: 8) {
            TextField("Enter URL", text: $viewModel.url)
                .textFieldStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(NSColor.textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                )
                .onSubmit {
                    viewModel.loadURL()
                }
            
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 20, height: 20)
            }
        }
    }
}

struct CopyButton: View {
    let content: String
    let image: NSImage?
    let label: String
    
    @State private var copied = false
    
    init(content: String, label: String, image: NSImage? = nil) {
        self.content = content
        self.label = label
        self.image = image
    }
    
    func copyToClipboard(includeAll: Bool = false) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        if includeAll, let image = image {
            // Create attributed string for rich text
            let attributedString = NSMutableAttributedString()
            
            // Add the text content
            attributedString.append(NSAttributedString(string: content + "\n\n"))
            
            // Create a cell to hold the image
            let cell = NSTextAttachmentCell(imageCell: image)
            
            // Create an attachment with the cell
            let attachment = NSTextAttachment()
            attachment.attachmentCell = cell
            
            // Calculate a reasonable size for the image
            let maxWidth: CGFloat = 600
            let aspectRatio = image.size.width / image.size.height
            let width = min(maxWidth, image.size.width)
            let height = width / aspectRatio
            
            // Set the bounds for the attachment
            attachment.bounds = CGRect(x: 0, y: 0, width: width, height: height)
            
            // Add the image attachment
            let imageString = NSAttributedString(attachment: attachment)
            attributedString.append(imageString)
            
            // Write both RTF and image to pasteboard
            if let rtfData = attributedString.rtf(from: NSRange(location: 0, length: attributedString.length)) {
                pasteboard.setData(rtfData, forType: .rtf)
            }
            
            // Also write the image separately
            pasteboard.writeObjects([image])
            
            // And the plain text as fallback
            pasteboard.setString(content, forType: .string)
            
        } else if let image = image {
            pasteboard.writeObjects([image])
        } else {
            pasteboard.setString(content, forType: .string)
        }
    }
    
    var body: some View {
        Button {
            copyToClipboard(includeAll: label == "Copy All Content")
            copied = true
            
            // Reset the copied state after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                copied = false
            }
        } label: {
            HStack(spacing: 4) {
                Text(label)
                Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                    .foregroundColor(copied ? .green : .gray)
            }
            .font(.system(size: 12))
        }
        .buttonStyle(.plain)
    }
}

struct SectionHeader: View {
    let title: String
    let content: String
    let image: NSImage?
    
    init(title: String, content: String, image: NSImage? = nil) {
        self.title = title
        self.content = content
        self.image = image
    }
    
    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
            
            Spacer()
            
            CopyButton(content: content, label: "Copy", image: image)
        }
    }
}

struct NotebookPanel: View {
    @ObservedObject var viewModel: WebViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            ClipModeButton(isActive: $viewModel.isClipModeActive)
                .padding()
            
            VStack(alignment: .leading, spacing: 12) {
                if let element = viewModel.selectedElement {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            // Copy All Button at the top
                            CopyButton(
                                content: """
                                Selected Element:
                                Tag: \(element.tagName)
                                Class: \(element.className)
                                
                                Text Content:
                                \(element.textContent)
                                
                                HTML:
                                \(element.content)
                                """,
                                label: "Copy All Content",
                                image: element.image
                            )
                            .padding(.bottom, 8)
                            
                            ElementMetadata(element: element)
                        }
                        .padding()
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "scissors")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                        
                        Text("Select an element to inspect")
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(width: 300)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct ElementMetadata: View {
    let element: SelectedElement
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Preview
            if let image = element.image {
                GroupBox("Preview") {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 200)
                        .padding(8)
                }
            }
            
            // Content
            GroupBox("Content") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(element.textContent)
                        .textSelection(.enabled)
                        .font(.system(.body, design: .monospaced))
                }
                .padding(8)
            }
            
            // Info
            GroupBox("Info") {
                VStack(alignment: .leading, spacing: 8) {
                    InfoRow(label: "Tag", value: element.tagName)
                    if !element.className.isEmpty {
                        InfoRow(label: "Class", value: element.className)
                    }
                    if let xpath = element.metadata["xpath"] as? String {
                        InfoRow(label: "XPath", value: xpath)
                    }
                    if let location = element.metadata["location"] as? [String: String],
                       let pathname = location["pathname"] {
                        InfoRow(label: "URL", value: pathname)
                    }
                }
                .padding(8)
            }
            
            // DOM Context
            if let domContext = element.metadata["domContext"] as? [String: Any] {
                GroupBox("DOM Context") {
                    VStack(alignment: .leading, spacing: 8) {
                        if let parent = domContext["parentTag"] as? String {
                            InfoRow(label: "Parent", value: parent)
                        }
                        if let childCount = domContext["childrenCount"] as? Int {
                            InfoRow(label: "Children", value: "\(childCount)")
                        }
                        if let siblings = domContext["siblings"] as? [String: String] {
                            if let prev = siblings["prev"] {
                                InfoRow(label: "Previous Sibling", value: prev)
                            }
                            if let next = siblings["next"] {
                                InfoRow(label: "Next Sibling", value: next)
                            }
                        }
                    }
                    .padding(8)
                }
            }
            
            // Computed Styles
            if let styles = element.metadata["styles"] as? [String: Any] {
                GroupBox("Computed Styles") {
                    VStack(alignment: .leading, spacing: 12) {
                        // Font Styles
                        if let font = styles["font"] as? [String: String] {
                            StyleSection(title: "Font", items: font)
                        }
                        
                        Divider()
                        
                        // Box Model
                        if let box = styles["box"] as? [String: [String: String]] {
                            StyleSection(title: "Box Model", items: [
                                "Padding": box["padding"]?.reduce("") { $0 + "\($1.value) " }.trimmingCharacters(in: .whitespaces) ?? "0",
                                "Margin": box["margin"]?.reduce("") { $0 + "\($1.value) " }.trimmingCharacters(in: .whitespaces) ?? "0",
                                "Border": box["border"]?.reduce("") { $0 + "\($1.value) " }.trimmingCharacters(in: .whitespaces) ?? "0"
                            ])
                        }
                        
                        Divider()
                        
                        // Layout
                        if let layout = styles["layout"] as? [String: String] {
                            StyleSection(title: "Layout", items: layout)
                        }
                    }
                    .padding(8)
                }
            }
            
            // Accessibility
            if let accessibility = element.metadata["accessibility"] as? [String: Any] {
                GroupBox("Accessibility") {
                    VStack(alignment: .leading, spacing: 8) {
                        if let role = accessibility["role"] as? String, role != "none" {
                            InfoRow(label: "Role", value: role)
                        }
                        if let ariaLabel = accessibility["ariaLabel"] as? String, !ariaLabel.isEmpty {
                            InfoRow(label: "ARIA Label", value: ariaLabel)
                        }
                        if let altText = accessibility["altText"] as? String, !altText.isEmpty {
                            InfoRow(label: "Alt Text", value: altText)
                        }
                        if let title = accessibility["title"] as? String, !title.isEmpty {
                            InfoRow(label: "Title", value: title)
                        }
                        if let tabIndex = accessibility["tabIndex"] as? Int, tabIndex != -1 {
                            InfoRow(label: "Tab Index", value: "\(tabIndex)")
                        }
                    }
                    .padding(8)
                }
            }
        }
        .padding()
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .frame(width: 60, alignment: .trailing)
                .foregroundColor(.secondary)
            
            Text(value)
                .textSelection(.enabled)
        }
    }
}

struct StyleSection: View {
    let title: String
    let items: [String: String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            
            ForEach(items.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                InfoRow(label: key, value: value)
            }
        }
    }
}

struct ClipModeButton: View {
    @Binding var isActive: Bool
    
    var body: some View {
        Button(action: { isActive.toggle() }) {
            VStack {
                Image(systemName: isActive ? "scissors.circle.fill" : "scissors.circle")
                    .font(.system(size: 24))
                Text(isActive ? "Clip Mode On" : "Clip Mode Off")
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isActive ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .help("Toggle Clip Mode")
    }
}

struct TextContent: View {
    let text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Text Content:")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text(text)
                .font(.body)
                .textSelection(.enabled)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

struct HTMLContent: View {
    let html: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("HTML Content:")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text(html)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct WebView: NSViewRepresentable {
    @ObservedObject var viewModel: WebViewModel
    
    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator(self)
    }
    
    func makeNSView(context: Context) -> WKWebView {
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences = preferences
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        configuration.applicationNameForUserAgent = "Snip/1.0"
        
        // Add script message handler
        configuration.userContentController.add(viewModel.scriptHandler, name: "elementSelected")
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsMagnification = true
        
        viewModel.setWebView(webView)
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        // Intentionally empty - updates handled by viewModel
    }
}

struct ContentView: View {
    @StateObject private var webViewModel = WebViewModel()
    
    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                NavigationBar(viewModel: webViewModel)
                
                if let errorMessage = webViewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding()
                }
                
                WebView(viewModel: webViewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 600, maxWidth: .infinity, maxHeight: .infinity)
            
            NotebookPanel(viewModel: webViewModel)
        }
        .onAppear {
            // Clear saved state on launch
            if let bundleID = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: bundleID)
                UserDefaults.standard.synchronize()
            }
        }
    }
}

struct SelectedElement {
    let content: String
    let tagName: String
    let className: String
    let textContent: String
    let image: NSImage?
    let metadata: [String: Any]
}

#Preview {
    ContentView()
}
