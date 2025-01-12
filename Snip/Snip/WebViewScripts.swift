import Foundation
import WebKit

class WebViewScriptHandler: NSObject, WKScriptMessageHandler {
    var onElementSelected: ((String, String, String, String, [String: Double], [String: String]?) -> Void)?
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "elementSelected",
              let dict = message.body as? [String: Any],
              let content = dict["content"] as? String,
              let tagName = dict["tagName"] as? String,
              let className = dict["className"] as? String,
              let textContent = dict["textContent"] as? String,
              let rect = dict["rect"] as? [String: Double],
              let restore = dict["restore"] as? [String: String] else {
            return
        }
        
        onElementSelected?(content, tagName, className, textContent, rect, restore)
    }
}

struct WebViewScripts {
    static let highlightScript = """
        if (!window._snipHighlightInit) {
            window._snipHighlightInit = true;
            
            let highlightedElement = null;
            let originalBackground = null;
            let originalOutline = null;
            
            function handleMouseOver(event) {
                if (highlightedElement) {
                    highlightedElement.style.background = originalBackground;
                    highlightedElement.style.outline = originalOutline;
                }
                
                highlightedElement = event.target;
                originalBackground = highlightedElement.style.background;
                originalOutline = highlightedElement.style.outline;
                
                highlightedElement.style.background = 'rgba(75, 137, 255, 0.1)';
                highlightedElement.style.outline = '2px solid rgb(75, 137, 255)';
            }
            
            function handleMouseOut(event) {
                if (highlightedElement) {
                    highlightedElement.style.background = originalBackground;
                    highlightedElement.style.outline = originalOutline;
                    highlightedElement = null;
                }
            }
            
            function extractFormattedText(element) {
                let texts = [];
                
                // Handle block elements by adding line breaks
                function isBlockElement(el) {
                    const blockStyles = window.getComputedStyle(el).display;
                    return blockStyles === 'block' || blockStyles === 'flex' || blockStyles === 'grid';
                }
                
                function processNode(node) {
                    if (node.nodeType === Node.TEXT_NODE) {
                        const text = node.textContent.trim();
                        if (text) texts.push(text);
                    } else if (node.nodeType === Node.ELEMENT_NODE) {
                        const isBlock = isBlockElement(node);
                        
                        // Add line break before block elements
                        if (isBlock && texts.length > 0) {
                            texts.push('\\n');
                        }
                        
                        // Process child nodes
                        node.childNodes.forEach(processNode);
                        
                        // Add line break after block elements
                        if (isBlock && texts.length > 0) {
                            texts.push('\\n');
                        }
                    }
                }
                
                processNode(element);
                
                // Clean up multiple line breaks and trim
                return texts.join(' ')
                    .replace(/\\s*\\n\\s*/g, '\\n')  // Clean up spaces around line breaks
                    .replace(/\\n{3,}/g, '\\n\\n')   // Max two consecutive line breaks
                    .trim();
            }
            
            function getElementRect(element) {
                const rect = element.getBoundingClientRect();
                const computedStyle = window.getComputedStyle(element);
                
                return {
                    x: rect.left + window.scrollX,
                    y: rect.top + window.scrollY,
                    width: rect.width,
                    height: rect.height,
                    devicePixelRatio: window.devicePixelRatio
                };
            }
            
            function handleClick(event) {
                event.preventDefault();
                event.stopPropagation();
                
                const element = event.target;
                const rect = getElementRect(element);
                
                // Store current styles
                const currentBackground = element.style.background;
                const currentOutline = element.style.outline;
                
                // Remove highlight effect
                element.style.background = originalBackground || '';
                element.style.outline = originalOutline || '';
                
                // Send message to take screenshot
                window.webkit.messageHandlers.elementSelected.postMessage({
                    content: element.outerHTML,
                    tagName: element.tagName.toLowerCase(),
                    className: element.className,
                    textContent: extractFormattedText(element),
                    rect: rect,
                    restore: {
                        background: currentBackground,
                        outline: currentOutline
                    }
                });
                
                // Restore highlight effect after a brief delay to allow screenshot
                setTimeout(() => {
                    element.style.background = currentBackground;
                    element.style.outline = currentOutline;
                }, 100);
                
                return false;
            }
            
            document.addEventListener('mouseover', handleMouseOver, true);
            document.addEventListener('mouseout', handleMouseOut, true);
            document.addEventListener('click', handleClick, true);
        }
    """
    
    static let disableHighlightScript = """
        if (window._snipHighlightInit) {
            document.removeEventListener('mouseover', handleMouseOver, true);
            document.removeEventListener('mouseout', handleMouseOut, true);
            document.removeEventListener('click', handleClick, true);
            
            if (highlightedElement) {
                highlightedElement.style.background = originalBackground;
                highlightedElement.style.outline = originalOutline;
                highlightedElement = null;
            }
            
            window._snipHighlightInit = false;
        }
    """
}
