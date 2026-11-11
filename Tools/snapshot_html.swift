// Loads a local HTML file in WKWebView, reports JS errors, writes a PNG snapshot.
//   swiftc -o /tmp/snap Tools/snapshot_html.swift && /tmp/snap page.html out.png [wait_seconds]
import AppKit
import WebKit

final class Delegate: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var errors: [String] = []
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) { errors.append("\(m.body)") }
}
let a = CommandLine.arguments
guard a.count >= 3 else { print("usage: snap page.html out.png [wait]"); exit(2) }
let wait = a.count > 3 ? Double(a[3]) ?? 2 : 2
let app = NSApplication.shared
let d = Delegate()
let cfg = WKWebViewConfiguration()
cfg.userContentController.add(d, name: "err")
cfg.userContentController.addUserScript(WKUserScript(source: "window.addEventListener('error',e=>webkit.messageHandlers.err.postMessage(e.message+' @'+e.lineno));", injectionTime: .atDocumentStart, forMainFrameOnly: true))
let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1100, height: 1000), configuration: cfg)
web.loadFileURL(URL(fileURLWithPath: a[1]), allowingReadAccessTo: URL(fileURLWithPath: "/"))
DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
    web.evaluateJavaScript("document.getElementById('sh') ? document.getElementById('sh').innerText + ' | ' + document.getElementById('clock').innerText : 'n/a'") { r, _ in
        print("page state:", r ?? "nil")
        web.takeSnapshot(with: nil) { img, _ in
            if let img, let t = img.tiffRepresentation, let rep = NSBitmapImageRep(data: t), let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: a[2])); print("snapshot written")
            }
            print("JS errors:", d.errors.isEmpty ? "none" : d.errors)
            exit(d.errors.isEmpty ? 0 : 1)
        }
    }
}
app.run()
