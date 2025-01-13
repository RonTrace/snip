import Foundation
import WebKit

class WebViewScriptHandler: NSObject, WKScriptMessageHandler {
    var onElementSelected: ((String, String, String, String, [String: Double], [String: String]?, [String: Any]) -> Void)?
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "elementSelected",
              let dict = message.body as? [String: Any],
              let content = dict["content"] as? String,
              let tagName = dict["tagName"] as? String,
              let className = dict["className"] as? String,
              let textContent = dict["textContent"] as? String,
              let rect = dict["rect"] as? [String: Double],
              let restore = dict["restore"] as? [String: String],
              let metadata = dict["metadata"] as? [String: Any],
              let xpath = dict["xpath"] as? String,
              let location = dict["location"] as? [String: String] else {
            return
        }
        
        let combinedMetadata: [String: Any] = [
            "metadata": metadata,
            "xpath": xpath,
            "location": location
        ]
        
        onElementSelected?(content, tagName, className, textContent, rect, restore, combinedMetadata)
    }
}

struct WebViewScripts {
    static let highlightScript = """
        window._snipHighlightInit = window._snipHighlightInit || {};
        
        if (!window._snipHighlightInit.active) {
            window._snipHighlightInit.active = true;
            window._snipHighlightInit.highlightedElement = null;
            window._snipHighlightInit.originalBackground = null;
            window._snipHighlightInit.originalOutline = null;
            
            window._snipHighlightInit.handleMouseOver = function(event) {
                if (window._snipHighlightInit.highlightedElement) {
                    window._snipHighlightInit.highlightedElement.style.background = window._snipHighlightInit.originalBackground;
                    window._snipHighlightInit.highlightedElement.style.outline = window._snipHighlightInit.originalOutline;
                }
                
                window._snipHighlightInit.highlightedElement = event.target;
                window._snipHighlightInit.originalBackground = window._snipHighlightInit.highlightedElement.style.background;
                window._snipHighlightInit.originalOutline = window._snipHighlightInit.highlightedElement.style.outline;
                
                window._snipHighlightInit.highlightedElement.style.background = 'rgba(75, 137, 255, 0.1)';
                window._snipHighlightInit.highlightedElement.style.outline = '2px solid rgb(75, 137, 255)';
            };
            
            window._snipHighlightInit.handleMouseOut = function(event) {
                if (window._snipHighlightInit.highlightedElement) {
                    window._snipHighlightInit.highlightedElement.style.background = window._snipHighlightInit.originalBackground;
                    window._snipHighlightInit.highlightedElement.style.outline = window._snipHighlightInit.originalOutline;
                    window._snipHighlightInit.highlightedElement = null;
                }
            };
            
            window._snipHighlightInit.extractFormattedText = function(element) {
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
            
            window._snipHighlightInit.getElementRect = function(element) {
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
            
            window._snipHighlightInit.getElementMetadata = function(element) {
                const style = window.getComputedStyle(element);
                const rect = element.getBoundingClientRect();
                
                // Get computed styles
                const styles = {
                    font: {
                        family: style.fontFamily,
                        size: style.fontSize,
                        weight: style.fontWeight,
                        color: style.color
                    },
                    box: {
                        padding: {
                            top: style.paddingTop,
                            right: style.paddingRight,
                            bottom: style.paddingBottom,
                            left: style.paddingLeft
                        },
                        margin: {
                            top: style.marginTop,
                            right: style.marginRight,
                            bottom: style.marginBottom,
                            left: style.marginLeft
                        },
                        border: {
                            top: style.borderTopWidth,
                            right: style.borderRightWidth,
                            bottom: style.borderBottomWidth,
                            left: style.borderLeftWidth
                        }
                    },
                    layout: {
                        display: style.display,
                        position: style.position,
                        zIndex: style.zIndex,
                        visibility: style.visibility,
                        backgroundColor: style.backgroundColor
                    }
                };
                
                // Get accessibility info
                const accessibility = {
                    role: element.getAttribute('role') || 'none',
                    tabIndex: element.tabIndex,
                    ariaLabel: element.getAttribute('aria-label') || '',
                    altText: element.getAttribute('alt') || '',
                    title: element.getAttribute('title') || ''
                };
                
                // Get DOM context
                const domContext = {
                    parentTag: element.parentElement ? element.parentElement.tagName.toLowerCase() : null,
                    childrenCount: element.children.length,
                    siblings: {
                        prev: element.previousElementSibling ? element.previousElementSibling.tagName.toLowerCase() : null,
                        next: element.nextElementSibling ? element.nextElementSibling.tagName.toLowerCase() : null
                    },
                    id: element.id || ''
                };
                
                return {
                    styles,
                    accessibility,
                    domContext
                };
            }
            
            window._snipHighlightInit.getXPath = function(element) {
                if (element.id !== '') {
                    return `//*[@id="${element.id}"]`;
                }
                
                if (element === document.body) {
                    return '/html/body';
                }
                
                let path = '';
                while (element.parentElement) {
                    let siblings = Array.from(element.parentElement.children);
                    let tagSiblings = siblings.filter(sibling => 
                        sibling.tagName === element.tagName
                    );
                    
                    if (tagSiblings.length > 1) {
                        let index = tagSiblings.indexOf(element) + 1;
                        path = `/${element.tagName.toLowerCase()}[${index}]${path}`;
                    } else {
                        path = `/${element.tagName.toLowerCase()}${path}`;
                    }
                    
                    element = element.parentElement;
                }
                
                return `/html${path}`;
            }
            
            window._snipHighlightInit.getLocationInfo = function() {
                return {
                    href: window.location.href,
                    pathname: window.location.pathname,
                    search: window.location.search,
                    hash: window.location.hash
                };
            }
            
            window._snipHighlightInit.handleClick = function(event) {
                event.preventDefault();
                event.stopPropagation();
                
                const element = event.target;
                const rect = window._snipHighlightInit.getElementRect(element);
                const metadata = window._snipHighlightInit.getElementMetadata(element);
                const xpath = window._snipHighlightInit.getXPath(element);
                const location = window._snipHighlightInit.getLocationInfo();
                
                // Store current styles
                const currentBackground = element.style.background;
                const currentOutline = element.style.outline;
                
                // Remove highlight effect
                element.style.background = window._snipHighlightInit.originalBackground || '';
                element.style.outline = window._snipHighlightInit.originalOutline || '';
                
                // Send message to take screenshot
                window.webkit.messageHandlers.elementSelected.postMessage({
                    content: element.outerHTML,
                    tagName: element.tagName.toLowerCase(),
                    className: element.className,
                    textContent: window._snipHighlightInit.extractFormattedText(element),
                    rect: rect,
                    metadata: metadata,
                    xpath: xpath,
                    location: location,
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
            
            document.addEventListener('mouseover', window._snipHighlightInit.handleMouseOver, true);
            document.addEventListener('mouseout', window._snipHighlightInit.handleMouseOut, true);
            document.addEventListener('click', window._snipHighlightInit.handleClick, true);
        }
    """
    
    static let disableHighlightScript = """
        if (window._snipHighlightInit && window._snipHighlightInit.active) {
            document.removeEventListener('mouseover', window._snipHighlightInit.handleMouseOver, true);
            document.removeEventListener('mouseout', window._snipHighlightInit.handleMouseOut, true);
            document.removeEventListener('click', window._snipHighlightInit.handleClick, true);
            
            if (window._snipHighlightInit.highlightedElement) {
                window._snipHighlightInit.highlightedElement.style.background = window._snipHighlightInit.originalBackground;
                window._snipHighlightInit.highlightedElement.style.outline = window._snipHighlightInit.originalOutline;
                window._snipHighlightInit.highlightedElement = null;
            }
            
            window._snipHighlightInit.active = false;
        }
    """
}
