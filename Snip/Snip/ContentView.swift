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
    @Published var selectedElement: (content: String, tagName: String, className: String, textContent: String, image: NSImage?)?
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
        scriptHandler.onElementSelected = { [weak self] content, tagName, className, textContent, rect, restore in
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
                            self?.selectedElement = (content, tagName, className, textContent, nil)
                        } else {
                            self?.selectedElement = (content, tagName, className, textContent, image)
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
                            ElementMetadata(element: element)
                            
                            Divider()
                            
                            if let image = element.image {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Visual Preview")
                                        .font(.headline)
                                    
                                    Image(nsImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxWidth: .infinity)
                                        .background(Color.gray.opacity(0.1))
                                        .cornerRadius(8)
                                }
                                
                                Divider()
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Text Content")
                                    .font(.headline)
                                
                                Text(element.textContent)
                                    .textSelection(.enabled)
                            }
                            
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("HTML")
                                    .font(.headline)
                                
                                HTMLContent(html: element.content)
                            }
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

struct ElementMetadata: View {
    let element: (content: String, tagName: String, className: String, textContent: String, image: NSImage?)
    
    var body: some View {
        Group {
            Text("Tag: \(element.tagName)")
                .font(.subheadline)
            
            if !element.className.isEmpty {
                Text("Class: \(element.className)")
                    .font(.subheadline)
            }
        }
        .foregroundColor(.secondary)
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

#Preview {
    ContentView()
}
