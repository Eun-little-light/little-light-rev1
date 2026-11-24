import Cocoa
import WebKit
import Darwin

// MARK: - Title bar drag strip (the web view covers the title bar)

final class DragStrip: NSView {
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { window?.zoom(nil) } else { window?.performDrag(with: event) }
    }
}

// 테두리 없는(.borderless) 미니 오버레이 모드에서도 키보드 입력을 받을 수 있도록 허용
final class GhostWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Ollama 서버 자동 실행 (앱이 띄운 경우에만 앱 종료 시 함께 종료)

final class OllamaLauncher {
    private var proc: Process?
    private let candidates = ["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama",
                              "/Applications/Ollama.app/Contents/Resources/ollama"]

    func ensureRunning(base: String) {
        guard let url = URL(string: base + "/api/tags"), ["localhost", "127.0.0.1"].contains(url.host ?? "") else { return }
        var req = URLRequest(url: url); req.timeoutInterval = 1.5
        URLSession.shared.dataTask(with: req) { _, resp, _ in
            if (resp as? HTTPURLResponse)?.statusCode == 200 { return }
            guard let bin = self.candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: bin)
            p.arguments = ["serve"]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
            self.proc = p
        }.resume()
    }

    func stop() { proc?.terminate() }
}

// MARK: - Mac 제어 도구

enum MacTools {
    static func run(_ name: String, _ a: [String: Any]) async -> String {
        switch name {
        case "open_app":       return openApp(str(a["name"]))
        case "open_url":       return openURL(str(a["url"]))
        case "web_search":     return webSearch(str(a["query"]), str(a["engine"]))
        case "system_info":    return await systemInfo()
        case "set_volume":     return await setVolume(int(a["level"]))
        case "set_brightness": return setBrightness(int(a["level"]))
        case "set_dark_mode":  return await setDarkMode(bool(a["enabled"]))
        case "create_note":    return await createNote(str(a["title"]), str(a["body"]))
        case "add_reminder":   return await addReminder(str(a["title"]), str(a["due"]))
        // agent-desktop(vercel-labs) 기반 범용 앱 조작: 접근성 트리를 읽고 ref로 조작 (헤드리스, 포인터 이동 없음)
        case "desktop_look":   return Desktop.look(str(a["app"]))
        case "desktop_click":  return Desktop.act(["click", str(a["ref"])])
        case "desktop_type":   return Desktop.act(["type", str(a["ref"]), "--stdin"], stdin: str(a["text"]))
        case "desktop_press":
            var args = ["press", str(a["keys"])]
            if !str(a["app"]).isEmpty { args += ["--app", str(a["app"])] }
            return Desktop.act(args)
        default:               return "알 수 없는 도구: \(name)"
        }
    }

    // ── 인자 정리
    static func str(_ v: Any?) -> String { (v as? String) ?? (v.map { "\($0)" } ?? "") }
    static func int(_ v: Any?) -> Int {
        let n = (v as? NSNumber)?.intValue ?? Int(str(v).filter { $0.isNumber }) ?? 0
        return max(0, min(100, n))
    }
    static func bool(_ v: Any?) -> Bool {
        if let b = v as? Bool { return b }
        return ["true", "1", "on", "yes", "켜"].contains { str(v).lowercased().contains($0) }
    }
    static func asq(_ s: String) -> String {   // AppleScript 문자열 이스케이프
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    @MainActor static func apple(_ src: String) -> (Bool, String) {
        var err: NSDictionary?
        let out = NSAppleScript(source: src)?.executeAndReturnError(&err)
        if let err = err {
            let msg = (err[NSAppleScript.errorMessage] as? String) ?? "\(err)"
            let num = (err[NSAppleScript.errorNumber] as? Int) ?? 0
            if num == -1743 { return (false, "자동화 권한이 없다. 시스템 설정 > 개인정보 보호 및 보안 > 자동화에서 작은 빛을 허용해야 한다.") }
            return (false, msg)
        }
        return (true, out?.stringValue ?? "")
    }

    static func shell(_ path: String, _ args: [String]) -> String {
        let p = Process(); let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: path); p.arguments = args
        p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return "" }
        p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    // ── 앱 열기: LaunchServices 이름 → 앱 폴더 검색(한글 표시 이름 포함)
    static func openApp(_ raw: String) -> String {
        let name = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ".app", with: "")
        guard !name.isEmpty else { return "앱 이름이 비어 있다." }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open"); p.arguments = ["-a", name]
        p.standardError = FileHandle.nullDevice
        if (try? p.run()) != nil { p.waitUntilExit(); if p.terminationStatus == 0 { return "\(name) 앱을 열었다." } }

        let dirs = ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                    NSHomeDirectory() + "/Applications", "/Applications/Utilities"]
        let key = name.lowercased().replacingOccurrences(of: " ", with: "")
        for d in dirs {
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: d) else { continue }
            for it in items where it.hasSuffix(".app") {
                let url = URL(fileURLWithPath: d).appendingPathComponent(it)
                let file = it.dropLast(4).lowercased().replacingOccurrences(of: " ", with: "")
                let shown = FileManager.default.displayName(atPath: url.path).lowercased()
                    .replacingOccurrences(of: ".app", with: "").replacingOccurrences(of: " ", with: "")
                if file == key || shown == key || file.contains(key) || shown.contains(key) {
                    NSWorkspace.shared.open(url)
                    return "\(FileManager.default.displayName(atPath: url.path)) 앱을 열었다."
                }
            }
        }
        return "'\(name)' 앱을 찾지 못했다."
    }

    static func openURL(_ s: String) -> String {
        guard let u = URL(string: s.trimmingCharacters(in: .whitespaces)),
              let sc = u.scheme?.lowercased(), sc == "http" || sc == "https" else { return "http/https 주소만 열 수 있다." }
        NSWorkspace.shared.open(u)
        return "\(u.absoluteString) 를 열었다."
    }

    static func webSearch(_ q: String, _ engine: String) -> String {
        guard !q.isEmpty else { return "검색어가 비어 있다." }
        let e = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        let url: String
        switch engine.lowercased() {
        case "youtube":  url = "https://www.youtube.com/results?search_query=\(e)"
        case "namuwiki": url = "https://namu.wiki/Search?q=\(e)"
        default:         url = "https://www.google.com/search?q=\(e)"
        }
        NSWorkspace.shared.open(URL(string: url)!)
        return "\(engine.isEmpty ? "google" : engine)에서 '\(q)' 검색 결과를 열었다."
    }

    static func systemInfo() async -> String {
        var lines: [String] = []
        let batt = shell("/usr/bin/pmset", ["-g", "batt"])
        if let r = batt.range(of: #"\d+%;[^;]*"#, options: .regularExpression) {
            lines.append("배터리: " + batt[r].replacingOccurrences(of: ";", with: ","))
        } else { lines.append("배터리: 없음(데스크톱) 또는 확인 불가") }
        if let v = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]),
           let free = v.volumeAvailableCapacityForImportantUsage, let total = v.volumeTotalCapacity {
            lines.append(String(format: "저장 공간: %.0fGB 남음 / 전체 %.0fGB", Double(free) / 1e9, Double(total) / 1e9))
        }
        lines.append(String(format: "메모리: %.0fGB", Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824))
        lines.append("macOS: " + ProcessInfo.processInfo.operatingSystemVersionString)
        let up = Int(ProcessInfo.processInfo.systemUptime)
        lines.append("가동 시간: \(up / 86400)일 \((up % 86400) / 3600)시간 \((up % 3600) / 60)분")
        let (ok, vol) = await apple("output volume of (get volume settings)")
        if ok { lines.append("볼륨: \(vol)%") }
        return lines.joined(separator: "\n")
    }

    static func setVolume(_ level: Int) async -> String {
        let (ok, msg) = await apple(level == 0 ? "set volume with output muted" : "set volume output volume \(level) without output muted")
        return ok ? (level == 0 ? "음소거했다." : "볼륨을 \(level)%로 맞췄다.") : "볼륨 변경 실패: \(msg)"
    }

    // 내장 디스플레이 밝기 (DisplayServices)
    static func setBrightness(_ level: Int) -> String {
        typealias SetB = @convention(c) (UInt32, Float) -> Int32
        guard let h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW),
              let sym = dlsym(h, "DisplayServicesSetBrightness") else { return "이 Mac에서는 밝기 조절을 지원하지 않는다." }
        let f = unsafeBitCast(sym, to: SetB.self)
        let r = f(CGMainDisplayID(), Float(level) / 100)
        return r == 0 ? "밝기를 \(level)%로 맞췄다." : "밝기 조절 실패(외장 모니터는 지원하지 않을 수 있다)."
    }

    static func setDarkMode(_ on: Bool) async -> String {
        let (ok, msg) = await apple("tell application \"System Events\" to tell appearance preferences to set dark mode to \(on)")
        return ok ? (on ? "다크 모드를 켰다." : "라이트 모드로 바꿨다.") : "다크 모드 변경 실패: \(msg)"
    }

    static func createNote(_ title: String, _ body: String) async -> String {
        let html = "<h1>\(esc(title))</h1>" + esc(body).replacingOccurrences(of: "\n", with: "<br>")
        let (ok, msg) = await apple("tell application \"Notes\" to make new note with properties {name:\"\(asq(title))\", body:\"\(asq(html))\"}")
        return ok ? "메모 '\(title)'를 만들었다." : "메모 만들기 실패: \(msg)"
    }

    static func addReminder(_ title: String, _ due: String) async -> String {
        var props = "{name:\"\(asq(title))\"}"
        var pre = ""
        let parts = due.split(whereSeparator: { "- :T".contains($0) }).compactMap { Int($0) }
        if parts.count >= 5 {
            pre = """
            set d to current date
            set day of d to 1
            set year of d to \(parts[0])
            set month of d to \(parts[1])
            set day of d to \(parts[2])
            set hours of d to \(parts[3])
            set minutes of d to \(parts[4])
            set seconds of d to 0

            """
            props = "{name:\"\(asq(title))\", remind me date:d}"
        }
        let (ok, msg) = await apple(pre + "tell application \"Reminders\" to make new reminder with properties \(props)")
        return ok ? "미리 알림 '\(title)'을 추가했다" + (parts.count >= 5 ? " (알림: \(due))." : ".") : "미리 알림 추가 실패: \(msg)"
    }

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
}

// MARK: - agent-desktop 연동

enum Desktop {
    static let bin = ["/opt/homebrew/bin/agent-desktop", "/usr/local/bin/agent-desktop"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    /// agent-desktop을 실행하고 JSON 응답을 돌려준다. 허용된 명령만 실행.
    static func run(_ args: [String], stdin: String? = nil) -> [String: Any]? {
        guard let bin = bin, let cmd = args.first, ["snapshot", "click", "type", "press"].contains(cmd) else { return nil }
        let p = Process(); let out = Pipe()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = args
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        if let stdin = stdin {
            let inp = Pipe(); p.standardInput = inp
            try? p.run()
            inp.fileHandleForWriting.write(Data(stdin.utf8)); try? inp.fileHandleForWriting.close()
        } else { try? p.run() }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func errorText(_ j: [String: Any]?) -> String {
        guard bin != nil else { return "agent-desktop이 설치되어 있지 않다. (brew install agent-desktop)" }
        guard let j = j else { return "agent-desktop 응답을 읽지 못했다." }
        let e = j["error"] as? [String: Any] ?? [:]
        let code = e["code"] as? String ?? "UNKNOWN"
        if code == "PERM_DENIED" || code.contains("PERMISSION") || (e["message"] as? String ?? "").lowercased().contains("accessibility") {
            return "접근성 권한이 없다. 시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용에서 '작은 빛'을 켜야 한다."
        }
        return "실패(\(code)): \(e["message"] as? String ?? "")"
    }

    /// 앱 화면을 읽어 조작 가능한 요소만 짧은 목록으로 만든다 (로컬 모델이 읽기 쉽게)
    static func look(_ app: String) -> String {
        guard !app.isEmpty else { return "앱 이름이 비어 있다." }
        let j = run(["snapshot", "--app", app, "-i", "--compact", "--timeout-ms", "5000"])
        guard let j = j, (j["ok"] as? Bool) == true, let data = j["data"] as? [String: Any] else { return errorText(j) }
        var lines: [String] = []
        func walk(_ n: [String: Any]) {
            if let ref = n["ref_id"] as? String {
                let role = n["role"] as? String ?? ""
                var name = (n["name"] as? String) ?? (n["value"] as? String) ?? ""
                if name.count > 40 { name = String(name.prefix(40)) + "…" }
                lines.append("\(ref) \(role) \(name.isEmpty ? "(이름 없음)" : name)")
            }
            for c in (n["children"] as? [[String: Any]] ?? []) { walk(c) }
        }
        if let tree = data["tree"] as? [String: Any] { walk(tree) }
        let total = lines.count
        let shown = lines.prefix(70).joined(separator: "\n")
        return "\(app) 화면의 조작 가능한 요소 \(total)개" + (total > 70 ? " (앞 70개만 표시)" : "") + ":\n" + shown
    }

    /// 클릭·입력·키 실행 결과 요약
    static func act(_ args: [String], stdin: String? = nil) -> String {
        let j = run(args, stdin: stdin)
        guard let j = j, (j["ok"] as? Bool) == true else { return errorText(j) }
        let d = (j["data"] as? [String: Any])?["disposition"] as? [String: Any]
        let delivery = d?["delivery"] as? String ?? "delivered"
        return "\(args[0]) 완료 (\(delivery)). 결과를 확인하려면 desktop_look으로 다시 본다."
    }
}

// MARK: - Claude 대체 (Claude Code CLI를 사용자의 claude.ai 로그인으로 실행)

enum ClaudeCLI {
    static var bin: String? {
        ["/opt/homebrew/bin/claude", "/usr/local/bin/claude",
         NSHomeDirectory() + "/.local/bin/claude", NSHomeDirectory() + "/.claude/local/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    var window: GhostWindow!
    var web: WKWebView!
    var dragStrip: DragStrip!
    let defaults = UserDefaults.standard
    let ollama = OllamaLauncher()

    private var isMiniMode = false
    private var savedNormalFrame: NSRect?
    private let normalBgColor = NSColor(red: 0.016, green: 0.047, blue: 0.075, alpha: 1)

    var base: String { defaults.string(forKey: "llmBase") ?? "http://localhost:11434" }

    func applicationDidFinishLaunching(_ note: Notification) {
        buildMenu()
        ollama.ensureRunning(base: base)

        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "native")

        let frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        window = GhostWindow(contentRect: frame,
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
        window.title = "작은 빛"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = normalBgColor
        window.minSize = NSSize(width: 900, height: 600)
        window.setFrameAutosaveName("GhostCoreMain")
        window.collectionBehavior = [.fullScreenPrimary]

        web = WKWebView(frame: frame, configuration: config)
        web.navigationDelegate = self
        web.setValue(false, forKey: "drawsBackground")
        web.autoresizingMask = [.width, .height]

        let container = NSView(frame: frame)
        container.autoresizingMask = [.width, .height]
        web.frame = container.bounds
        container.addSubview(web)

        let strip = DragStrip(frame: NSRect(x: 80, y: frame.height - 34, width: frame.width - 80, height: 34))
        strip.autoresizingMask = [.width, .minYMargin]
        container.addSubview(strip)
        self.dragStrip = strip

        window.contentView = container
        if !window.setFrameUsingName("GhostCoreMain") { window.center() }
        window.makeKeyAndOrderFront(nil)

        let res = Bundle.main.resourceURL!.appendingPathComponent("web")
        web.loadFileURL(res.appendingPathComponent("index.html"), allowingReadAccessTo: res)
        NSApp.activate(ignoringOtherApps: true)
        scheduleSnapshotIfRequested()

        // 창이 가려지거나 최소화되면 화면 애니메이션을 멈추도록 페이지에 알림 (보일 때 다시 시작)
        NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.js("window.__setVisible", [self.window.occlusionState.contains(.visible)])
        }
    }

    // 문서용 스크린샷: `작은 빛.app/Contents/MacOS/GhostCore --snapshot <파일.png> [--delay 초] [--quit]`
    func scheduleSnapshotIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        let out = URL(fileURLWithPath: args[i + 1])
        var delay = 8.0
        if let d = args.firstIndex(of: "--delay"), d + 1 < args.count, let v = Double(args[d + 1]) { delay = v }
        let quit = args.contains("--quit")
        window.setContentSize(NSSize(width: 1440, height: 900))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.web.takeSnapshot(with: nil) { image, _ in
                if let image = image, let tiff = image.tiffRepresentation,
                   let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: out)
                }
                if quit { NSApp.terminate(nil) }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        unloadModel()
        ollama.stop()
    }

    /// 앱이 켜져 있는 동안 메모리에 붙잡아 둔 모델을 종료할 때 내려 놓는다 (최대 1.5초 대기)
    func unloadModel() {
        let model = defaults.string(forKey: "llmModel") ?? "qwen3:8b"
        guard let url = URL(string: base + "/api/generate"),
              let body = try? JSONSerialization.data(withJSONObject: ["model": model, "keep_alive": 0]) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 1.5
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { _, _, _ in done.signal() }.resume()
        _ = done.wait(timeout: .now() + 1.5)
    }

    // MARK: JS 콜백
    func js(_ fn: String, _ args: [Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: args, options: [.fragmentsAllowed]),
              let s = String(data: data, encoding: .utf8) else { return }
        let inner = String(s.dropFirst().dropLast())
        DispatchQueue.main.async { self.web.evaluateJavaScript("\(fn)(\(inner))", completionHandler: nil) }
    }
    func reply(_ id: Int, _ ok: Bool, _ data: String) { js("window.__nativeReply", [id, ok, data]) }

    // MARK: JS -> Swift
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let cmd = body["cmd"] as? String else { return }
        let id = (body["id"] as? NSNumber)?.intValue ?? 0
        switch cmd {
        case "ready":
            pushConfig()
        case "saveConfig":
            for k in ["base", "model", "mode"] { if let v = body[k] as? String { defaults.set(v, forKey: "llm" + k.capitalized) } }
            if let t = body["tools"] as? Bool { defaults.set(t, forKey: "llmTools") }
            if let c = body["claude"] as? Bool { defaults.set(c, forKey: "llmClaude") }
            ollama.ensureRunning(base: base)
        case "toggleFullscreen":
            window.toggleFullScreen(nil)
        case "toggleMini":
            toggleMiniMode()
        case "beep":
            NSSound(named: "Glass")?.play()
        case "http":
            httpGet(id, body["url"] as? String ?? "")
        case "httpStream":
            httpStream(id, body["url"] as? String ?? "", body["body"] as? String ?? "")
        case "claudeAsk":
            claudeAsk(id, system: body["system"] as? String ?? "", prompt: body["prompt"] as? String ?? "")
        case "tool":
            let name = body["name"] as? String ?? ""
            let args = body["args"] as? [String: Any] ?? [:]
            Task { let r = await MacTools.run(name, args); self.reply(id, true, r) }
        default:
            break
        }
    }

    /// 로컬 LLM이 대답하지 못할 때 Claude Code CLI로 대신 묻는다. 도구는 모두 끄고(대답만),
    /// 세션은 저장하지 않으며, 사용자 설정·훅은 읽지 않는다. 출력은 stream-json 한 줄씩 페이지로 전달.
    func claudeAsk(_ id: Int, system: String, prompt: String) {
        guard let bin = ClaudeCLI.bin else { reply(id, false, "claude CLI가 설치되어 있지 않다."); return }
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: bin)
            p.arguments = ["-p", "--output-format", "stream-json", "--include-partial-messages", "--verbose",
                           "--tools", "", "--system-prompt", system,
                           "--no-session-persistence", "--setting-sources", ""]
            p.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
            p.environment = env
            let out = Pipe(), err = Pipe(), inp = Pipe()
            p.standardOutput = out; p.standardError = err; p.standardInput = inp
            var errData = Data()
            let errLock = NSLock()
            err.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                errLock.lock(); errData.append(d); errLock.unlock()
            }
            do { try p.run() } catch {
                self.reply(id, false, "claude 실행 실패: \(error.localizedDescription)"); return
            }
            inp.fileHandleForWriting.write(Data(prompt.utf8))
            try? inp.fileHandleForWriting.close()
            DispatchQueue.global().asyncAfter(deadline: .now() + 120) { if p.isRunning { p.terminate() } }

            var buf = Data()
            let fh = out.fileHandleForReading
            func emitLines() {
                while let r = buf.firstRange(of: Data([0x0A])) {
                    let line = buf.subdata(in: buf.startIndex..<r.lowerBound)
                    buf.removeSubrange(buf.startIndex..<r.upperBound)
                    if let s = String(data: line, encoding: .utf8), !s.isEmpty { self.js("window.__nativeLine", [id, s]) }
                }
            }
            while true {
                let d = fh.availableData
                if d.isEmpty { break }
                buf.append(d); emitLines()
            }
            if !buf.isEmpty, let s = String(data: buf, encoding: .utf8), !s.isEmpty { self.js("window.__nativeLine", [id, s]) }
            p.waitUntilExit()
            err.fileHandleForReading.readabilityHandler = nil
            errLock.lock(); let errText = String(data: errData, encoding: .utf8) ?? ""; errLock.unlock()
            let ok = p.terminationStatus == 0
            self.reply(id, ok, ok ? "" : String(errText.suffix(300)))
        }
    }

    func pushConfig() {
        let cfg: [String: Any] = [
            "base": base,
            "model": defaults.string(forKey: "llmModel") ?? "qwen3:8b",
            "mode": defaults.string(forKey: "llmMode") ?? "AUTO",
            "tools": defaults.object(forKey: "llmTools") as? Bool ?? true,
            "claude": defaults.object(forKey: "llmClaude") as? Bool ?? true,
            "claudeCLI": ClaudeCLI.bin != nil,
        ]
        js("window.__applyNativeConfig", [cfg])
    }

    @objc func toggleMiniMode() {
        if window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
            return
        }

        isMiniMode.toggle()

        if isMiniMode {
            savedNormalFrame = window.frame
            dragStrip.isHidden = true

            window.minSize = NSSize(width: 260, height: 300)
            window.styleMask = [.borderless]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isMovableByWindowBackground = true

            if let screen = window.screen ?? NSScreen.main {
                let vis = screen.visibleFrame
                let miniFrame = NSRect(
                    x: vis.maxX - 324,
                    y: vis.minY + 24,
                    width: 300,
                    height: 360
                )
                window.setFrame(miniFrame, display: true, animate: true)
            }
        } else {
            dragStrip.isHidden = false

            window.minSize = NSSize(width: 900, height: 600)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.title = "작은 빛"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isOpaque = true
            window.backgroundColor = normalBgColor
            window.hasShadow = true
            window.level = .normal
            window.collectionBehavior = [.fullScreenPrimary]
            window.isMovableByWindowBackground = false

            let restoreFrame = savedNormalFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            window.setFrame(restoreFrame, display: true, animate: true)
            if savedNormalFrame == nil { window.center() }
        }

        window.makeKeyAndOrderFront(nil)
        js("window.__setMiniMode", [isMiniMode])
    }

    // MARK: HTTP (Ollama)
    func validURL(_ s: String) -> URL? {
        guard let u = URL(string: s), let sc = u.scheme, sc == "http" || sc == "https" else { return nil }
        return u
    }

    func httpGet(_ id: Int, _ s: String) {
        guard let u = validURL(s) else { reply(id, false, "잘못된 주소"); return }
        var req = URLRequest(url: u); req.timeoutInterval = 4
        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err = err { self.reply(id, false, err.localizedDescription); return }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            self.reply(id, code == 200, code == 200 ? text : "HTTP \(code) \(text)")
        }.resume()
    }

    func httpStream(_ id: Int, _ s: String, _ body: String) {
        guard let u = validURL(s) else { reply(id, false, "잘못된 주소"); return }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body.data(using: .utf8)
        req.timeoutInterval = 300
        Task {
            do {
                let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if code != 200 {
                    var text = ""
                    for try await line in bytes.lines { text += line }
                    self.reply(id, false, "HTTP \(code) \(text)")
                    return
                }
                for try await line in bytes.lines { self.js("window.__nativeLine", [id, line]) }
                self.reply(id, true, "")
            } catch {
                self.reply(id, false, error.localizedDescription)
            }
        }
    }

    // 외부 링크는 기본 브라우저로
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = action.request.url, action.navigationType == .linkActivated, url.scheme?.hasPrefix("http") == true {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }

    // MARK: Menu
    @objc func openSettings() { web.evaluateJavaScript("window.openConfig && window.openConfig()", completionHandler: nil) }
    @objc func reloadPage() { web.reload() }

    func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "작은 빛에 관하여", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "링크 설정…", action: #selector(openSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "작은 빛 가리기", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "작은 빛 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "편집")
        edit.addItem(withTitle: "실행 취소", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "실행 복귀", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "오려두기", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "복사하기", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "전체 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        let viewItem = NSMenuItem(); main.addItem(viewItem)
        let view = NSMenu(title: "보기")
        let fs = NSMenuItem(title: "전체 화면 전환", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fs.keyEquivalentModifierMask = [.command, .control]
        view.addItem(fs)
        view.addItem(withTitle: "미니 고스트 오버레이", action: #selector(toggleMiniMode), keyEquivalent: "g")
        view.addItem(withTitle: "새로 고침", action: #selector(reloadPage), keyEquivalent: "r")
        viewItem.submenu = view

        let winItem = NSMenuItem(); main.addItem(winItem)
        let win = NSMenu(title: "윈도우")
        win.addItem(withTitle: "최소화", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        win.addItem(withTitle: "닫기", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        winItem.submenu = win
        NSApp.windowsMenu = win

        NSApp.mainMenu = main
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
