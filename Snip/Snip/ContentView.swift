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
    let image: NSImage?
    let content: String
    let element: ElementData
    @State private var isCopied = false
    
    init(image: NSImage? = nil, content: String, element: ElementData) {
        self.image = image
        self.content = content
        self.element = element
    }
    
    var body: some View {
        Button {
            copyToClipboard()
        } label: {
            Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                .foregroundColor(isCopied ? .green : .primary)
        }
        .buttonStyle(.plain)
    }
    
    func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        if let image = image {
            if content.isEmpty {
                print("Debug: Copying image only")
                pasteboard.writeObjects([image])
            } else {
                print("Debug: Copying both image and text")
                
                // Create the formatted text
                let formattedText = """
                Content:
                \(content)
                
                Info:
                Tag: \(element.tagName)
                Class: \(element.className)\(element.className.isEmpty ? "" : "\n")\
                \((element.metadata["xpath"] as? String).map { "XPath: \($0)\n" } ?? "")\
                \((element.metadata["location"] as? [String: String])?.compactMapValues { $0 }["pathname"].map { "URL: \($0)" } ?? "")
                """
                
                print("Debug: Text content:", formattedText)
                
                // Create an attributed string with both image and text
                let attributedString = NSMutableAttributedString()
                
                // Add the image
                let attachment = NSTextAttachment()
                attachment.image = image
                let imageString = NSAttributedString(attachment: attachment)
                attributedString.append(imageString)
                
                // Add a line break after the image
                attributedString.append(NSAttributedString(string: "\n\n"))
                
                // Add the text
                attributedString.append(NSAttributedString(string: formattedText))
                
                // Declare the types we'll support
                pasteboard.declareTypes([.rtf, .string], owner: nil)
                
                // Write the RTF version with both image and text
                if let rtfData = attributedString.rtf(from: NSRange(location: 0, length: attributedString.length)) {
                    print("Debug: Adding RTF data, size:", rtfData.count)
                    pasteboard.setData(rtfData, forType: .rtf)
                }
                
                // Also write plain text version as fallback
                pasteboard.setString(formattedText, forType: .string)
                
                print("Debug: Available types after copy:", pasteboard.types ?? [])
            }
        } else if !content.isEmpty {
            pasteboard.setString(content, forType: .string)
        }
        
        isCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isCopied = false
        }
    }
}

struct ModuleBox<Content: View>: View {
    let title: String
    let copyContent: String
    let copyImage: NSImage?
    let content: Content
    
    init(title: String, copyContent: String, copyImage: NSImage? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.copyContent = copyContent
        self.copyImage = copyImage
        self.content = content()
    }
    
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.headline)
                    
                    Spacer()
                    
                    CopyButton(
                        image: copyImage,
                        content: copyContent,
                        element: ElementData()
                    )
                }
                
                content
            }
            .padding(8)
        }
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
            
            CopyButton(
                image: image,
                content: content,
                element: ElementData()
            )
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
                            if let element = viewModel.selectedElement {
                                let contentText = """
                                    Content:
                                    \(element.textContent)
                                    
                                    Info:
                                    Tag: \(element.tagName)
                                    Class: \(element.className)\(element.className.isEmpty ? "" : "\n")\
                                    \((element.metadata["xpath"] as? String).map { "XPath: \($0)\n" } ?? "")\
                                    \((element.metadata["location"] as? [String: String])?.compactMapValues { $0 }["pathname"].map { "URL: \($0)" } ?? "")
                                    """
                                CopyButton(
                                    image: element.image,
                                    content: contentText.trimmingCharacters(in: .whitespacesAndNewlines),
                                    element: ElementData(tagName: element.tagName, className: element.className, metadata: element.metadata)
                                )
                                .padding(.bottom, 8)
                            }
                            
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
                ModuleBox(title: "Preview", copyContent: "", copyImage: image) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 200)
                }
            }
            
            // Content
            ModuleBox(title: "Content", copyContent: element.textContent) {
                Text(element.textContent)
                    .textSelection(.enabled)
                    .font(.system(.body, design: .monospaced))
            }
            
            // Info
            ModuleBox(title: "Info", copyContent: """
                Tag: \(element.tagName)
                Class: \(element.className)
                XPath: \(element.metadata["xpath"] as? String ?? "")
                URL: \(element.metadata["location"] as? [String: String] ?? [:])["pathname"] ?? ""
                """) {
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
            }
            
            // DOM Context
            if let domContext = element.metadata["domContext"] as? [String: Any] {
                ModuleBox(title: "DOM Context", copyContent: """
                    Parent: \(domContext["parentTag"] as? String ?? "")
                    Children: \(domContext["childrenCount"] as? Int ?? 0)
                    Previous: \((domContext["siblings"] as? [String: String] ?? [:])["prev"] ?? "")
                    Next: \((domContext["siblings"] as? [String: String] ?? [:])["next"] ?? "")
                    """) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let parent = domContext["parentTag"] as? String {
                            InfoRow(label: "Parent", value: parent)
                        }
                        if let childCount = domContext["childrenCount"] as? Int {
                            InfoRow(label: "Children", value: "\(childCount)")
                        }
                        if let siblings = domContext["siblings"] as? [String: String] {
                            if let prev = siblings["prev"] {
                                InfoRow(label: "Previous", value: prev)
                            }
                            if let next = siblings["next"] {
                                InfoRow(label: "Next", value: next)
                            }
                        }
                    }
                }
            }
            
            // Computed Styles
            if let styles = element.metadata["styles"] as? [String: Any] {
                ModuleBox(title: "Computed Styles", copyContent: """
                    Font: \(styles["font"] as? [String: String] ?? [:])
                    Box Model:
                      Padding: \((styles["box"] as? [String: [String: String]] ?? [:])["padding"] ?? [:])
                      Margin: \((styles["box"] as? [String: [String: String]] ?? [:])["margin"] ?? [:])
                      Border: \((styles["box"] as? [String: [String: String]] ?? [:])["border"] ?? [:])
                    Layout: \(styles["layout"] as? [String: String] ?? [:])
                    """) {
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
                }
            }
            
            // Accessibility
            if let accessibility = element.metadata["accessibility"] as? [String: Any] {
                ModuleBox(title: "Accessibility", copyContent: """
                    Role: \(accessibility["role"] as? String ?? "")
                    ARIA Label: \(accessibility["ariaLabel"] as? String ?? "")
                    Alt Text: \(accessibility["altText"] as? String ?? "")
                    Title: \(accessibility["title"] as? String ?? "")
                    Tab Index: \(accessibility["tabIndex"] as? Int ?? -1)
                    """) {
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

struct ElementData {
    let tagName: String
    let className: String
    let metadata: [String: Any]
    
    init(tagName: String = "", className: String = "", metadata: [String: Any] = [:]) {
        self.tagName = tagName
        self.className = className
        self.metadata = metadata
    }
}

#Preview {
    ContentView()
}
