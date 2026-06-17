// mmd-render : rendu PNG d'un diagramme Mermaid via WKWebView (Apple).
// Lit du Mermaid en entrée, charge un HTML avec Mermaid.js inline (bundlé
// dans Resources/), attend que le SVG soit produit puis screenshot le WKWebView.
//
// Usage : mmd-render -i input.mmd -o output.png [-w width] [-b background]
// Compatible CLI mmdc (les flags -b et autres sont acceptés et ignorés).
//
// Build : xcrun -sdk macosx swiftc -O mmd-render.swift -o mmd-render

import Cocoa
import WebKit

final class Renderer: NSObject, WKNavigationDelegate {
    let outPath: String
    let width: Int
    var window: NSWindow!
    var webView: WKWebView!

    init(html: String, width: Int, outPath: String) {
        self.outPath = outPath
        self.width = width
        super.init()
        let rect = NSRect(x: 0, y: 0, width: width, height: width)
        let config = WKWebViewConfiguration()
        self.webView = WKWebView(frame: rect, configuration: config)
        self.webView.navigationDelegate = self
        // Fenêtre off-screen, transparente, sans bordure.
        self.window = NSWindow(
            contentRect: rect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.window.contentView = self.webView
        self.window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        self.window.alphaValue = 0
        self.window.makeKeyAndOrderFront(nil)
        self.webView.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pollForSVG(attempts: 100)
    }

    func pollForSVG(attempts: Int) {
        if attempts <= 0 { fail("timeout en attendant Mermaid"); return }
        let js = "document.querySelector('svg') ? 1 : 0"
        webView.evaluateJavaScript(js) { (result, _) in
            if let r = result as? Int, r > 0 {
                self.measure()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.pollForSVG(attempts: attempts - 1)
                }
            }
        }
    }

    func measure() {
        let js = """
        (function() {
          var svg = document.querySelector('svg');
          var r = svg.getBoundingClientRect();
          return JSON.stringify({ w: Math.ceil(r.right + 8), h: Math.ceil(r.bottom + 8) });
        })();
        """
        webView.evaluateJavaScript(js) { (result, _) in
            var w = self.width
            var h = self.width
            if let s = result as? String,
               let d = s.data(using: .utf8),
               let j = try? JSONSerialization.jsonObject(with: d) as? [String: Double] {
                w = max(Int(j["w"] ?? Double(self.width)), 100)
                h = max(Int(j["h"] ?? Double(self.width)), 100)
            }
            let frame = NSRect(x: 0, y: 0, width: w, height: h)
            self.window.setContentSize(frame.size)
            self.webView.frame = frame
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                self.snapshot()
            }
        }
    }

    func snapshot() {
        let config = WKSnapshotConfiguration()
        config.afterScreenUpdates = true
        webView.takeSnapshot(with: config) { (image, error) in
            guard let image = image else {
                self.fail("snapshot: \(error?.localizedDescription ?? "inconnu")")
                return
            }
            guard let tiff = image.tiffRepresentation,
                  let bmp = NSBitmapImageRep(data: tiff),
                  let png = bmp.representation(using: .png, properties: [:]) else {
                self.fail("encodage PNG impossible")
                return
            }
            do {
                try png.write(to: URL(fileURLWithPath: self.outPath))
                exit(0)
            } catch {
                self.fail("ecriture: \(error.localizedDescription)")
            }
        }
    }

    func fail(_ msg: String) {
        FileHandle.standardError.write(("mmd-render: " + msg + "\n").data(using: .utf8)!)
        exit(1)
    }
}

// ---- arguments ----
var inputPath = ""
var outputPath = ""
var width = 1600
do {
    let args = CommandLine.arguments
    var i = 1
    while i < args.count {
        let a = args[i]
        switch a {
        case "-i":
            if i + 1 < args.count { inputPath = args[i + 1]; i += 2 } else { i += 1 }
        case "-o":
            if i + 1 < args.count { outputPath = args[i + 1]; i += 2 } else { i += 1 }
        case "-w":
            if i + 1 < args.count, let w = Int(args[i + 1]) { width = w; i += 2 } else { i += 1 }
        case "-b":
            // -b transparent etc. (compat mmdc) : ignoré, fond toujours transparent
            i += 2
        default:
            i += 1
        }
    }
}
guard !inputPath.isEmpty, !outputPath.isEmpty else {
    FileHandle.standardError.write("usage: mmd-render -i input.mmd -o output.png [-w 1600]\n".data(using: .utf8)!)
    exit(2)
}

// ---- source ----
let source: String
do {
    source = try String(contentsOfFile: inputPath, encoding: .utf8)
} catch {
    FileHandle.standardError.write("mmd-render: lecture \(inputPath) impossible\n".data(using: .utf8)!)
    exit(3)
}

// ---- mermaid.min.js ----
let exeURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
let exeDir = exeURL.deletingLastPathComponent()
let candidates = [
    exeDir.appendingPathComponent("../Resources/mermaid.min.js"),
    exeDir.appendingPathComponent("mermaid.min.js"),
    URL(fileURLWithPath: "/Applications/mSM.app/Contents/Resources/mermaid.min.js"),
]
var mermaidJS = ""
for c in candidates {
    if let content = try? String(contentsOf: c.standardizedFileURL, encoding: .utf8) {
        mermaidJS = content
        break
    }
}
guard !mermaidJS.isEmpty else {
    FileHandle.standardError.write("mmd-render: mermaid.min.js introuvable\n".data(using: .utf8)!)
    exit(4)
}

// ---- HTML ----
let escaped = source
    .replacingOccurrences(of: "&", with: "&amp;")
    .replacingOccurrences(of: "<", with: "&lt;")
    .replacingOccurrences(of: ">", with: "&gt;")

let html = """
<!DOCTYPE html>
<html><head><meta charset="UTF-8">
<style>html,body{margin:0;background:transparent;font-family:-apple-system,sans-serif;}</style>
<script>\(mermaidJS)</script>
</head><body>
<div class="mermaid">\(escaped)</div>
<script>
  mermaid.initialize({ startOnLoad: true, theme: 'default', securityLevel: 'loose' });
</script>
</body></html>
"""

// ---- run ----
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let renderer = Renderer(html: html, width: width, outPath: outputPath)
_ = renderer
app.run()
