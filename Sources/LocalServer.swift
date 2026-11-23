import Foundation
import Network

/// 极简只读 HTTP 服务，只监听 127.0.0.1。
/// WKWebView 里用 file:// 打开时 XHR 会被同源策略挡住，所以必须有 http 源。
final class LocalServer {

    private let root: URL
    private let queue = DispatchQueue(label: "saoweb.http", qos: .userInitiated, attributes: .concurrent)
    private let startSem = DispatchSemaphore(value: 0)
    private var listener: NWListener?
    private(set) var port: UInt16 = 0

    private var notFoundLog: [String] = []
    private let nfLock = NSLock()

    func recentNotFound() -> [String] {
        nfLock.lock()
        defer { nfLock.unlock() }
        return Array(notFoundLog.suffix(20))
    }

    private func recordNotFound(_ p: String) {
        nfLock.lock()
        notFoundLog.append(p)
        if notFoundLog.count > 300 {
            notFoundLog.removeFirst(150)
        }
        nfLock.unlock()
    }

    init(root: URL) {
        self.root = root.standardizedFileURL
    }

    /// 返回实际端口，失败返回 nil
    func start() -> UInt16? {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params, on: .any)
            self.listener = l

            l.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    if let p = l.port { self.port = p.rawValue }
                    self.startSem.signal()
                case .failed, .cancelled:
                    self.startSem.signal()
                default:
                    break
                }
            }
            l.newConnectionHandler = { [weak self] conn in
                self?.accept(conn)
            }
            l.start(queue: queue)
            _ = startSem.wait(timeout: .now() + 5)
            return port == 0 ? nil : port
        } catch {
            NSLog("LocalServer start failed: \(error)")
            return nil
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - 连接处理

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        readHead(conn, buffer: Data())
    }

    private func readHead(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self = self else { conn.cancel(); return }
            var buf = buffer
            if let d = data { buf.append(d) }

            if let headEnd = buf.range(of: Data("\r\n\r\n".utf8)) {
                let headData = buf.subdata(in: 0..<headEnd.lowerBound)
                let head = String(data: headData, encoding: .utf8) ?? ""
                self.respond(head: head, conn: conn)
                return
            }
            if error != nil || isComplete || buf.count > 512 * 1024 {
                conn.cancel()
                return
            }
            self.readHead(conn, buffer: buf)
        }
    }

    private func respond(head: String, conn: NWConnection) {
        let lines = head.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { conn.cancel(); return }
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { conn.cancel(); return }
        let method = parts[0]
        let target = parts[1]

        var rangeStart: Int64 = -1
        var rangeEnd: Int64 = -1
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if key == "range", value.lowercased().hasPrefix("bytes=") {
                let spec = value.dropFirst(6)
                let segs = spec.split(separator: "-", omittingEmptySubsequences: false)
                if segs.count == 2 {
                    if let s = Int64(segs[0]) { rangeStart = s }
                    if let e = Int64(segs[1]) { rangeEnd = e }
                }
            }
        }

        guard let file = resolve(target) else {
            recordNotFound(target)
            sendText(conn, status: "404 Not Found", body: "Not Found: \(target)")
            return
        }

        let attrs = try? FileManager.default.attributesOfItem(atPath: file.path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        let mime = LocalServer.mimeType(for: file.lastPathComponent)
        let isHead = (method == "HEAD")

        guard let fh = try? FileHandle(forReadingFrom: file) else {
            sendText(conn, status: "403 Forbidden", body: "Forbidden")
            return
        }

        if rangeStart >= 0 {
            if rangeStart >= size {
                fh.closeFile()
                sendText(conn, status: "416 Range Not Satisfiable", body: "bad range")
                return
            }
            var end = rangeEnd
            if end < 0 || end >= size { end = size - 1 }
            let chunk = end - rangeStart + 1
            let header = "HTTP/1.1 206 Partial Content\r\n"
                + "Content-Type: \(mime)\r\n"
                + "Content-Length: \(chunk)\r\n"
                + "Content-Range: bytes \(rangeStart)-\(end)/\(size)\r\n"
                + "Accept-Ranges: bytes\r\n"
                + "Cache-Control: no-cache\r\n"
                + "Connection: close\r\n\r\n"
            fh.seek(toFileOffset: UInt64(rangeStart))
            conn.send(content: Data(header.utf8), completion: .contentProcessed { _ in
                if isHead {
                    fh.closeFile()
                    conn.cancel()
                    return
                }
                self.sendBody(conn, handle: fh, remaining: chunk)
            })
        } else {
            let header = "HTTP/1.1 200 OK\r\n"
                + "Content-Type: \(mime)\r\n"
                + "Content-Length: \(size)\r\n"
                + "Accept-Ranges: bytes\r\n"
                + "Cache-Control: no-cache\r\n"
                + "Connection: close\r\n\r\n"
            conn.send(content: Data(header.utf8), completion: .contentProcessed { _ in
                if isHead {
                    fh.closeFile()
                    conn.cancel()
                    return
                }
                self.sendBody(conn, handle: fh, remaining: size)
            })
        }
    }

    private func sendBody(_ conn: NWConnection, handle: FileHandle, remaining: Int64) {
        guard remaining > 0 else {
            handle.closeFile()
            conn.send(content: nil, contentContext: .defaultMessage, isComplete: true,
                      completion: .contentProcessed { _ in conn.cancel() })
            return
        }
        let want = Int(min(Int64(256 * 1024), remaining))
        let data = handle.readData(ofLength: want)
        if data.isEmpty {
            handle.closeFile()
            conn.cancel()
            return
        }
        conn.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self = self, error == nil else {
                handle.closeFile()
                conn.cancel()
                return
            }
            self.sendBody(conn, handle: handle, remaining: remaining - Int64(data.count))
        })
    }

    private func sendText(_ conn: NWConnection, status: String, body: String) {
        let payload = Data(body.utf8)
        let header = "HTTP/1.1 \(status)\r\n"
            + "Content-Type: text/plain; charset=utf-8\r\n"
            + "Content-Length: \(payload.count)\r\n"
            + "Connection: close\r\n\r\n"
        conn.send(content: Data(header.utf8), completion: .contentProcessed { _ in
            conn.send(content: payload, completion: .contentProcessed { _ in
                conn.send(content: nil, contentContext: .defaultMessage, isComplete: true,
                          completion: .contentProcessed { _ in conn.cancel() })
            })
        })
    }

    /// 把请求路径安全地映射到 root 下的文件
    private func resolve(_ target: String) -> URL? {
        var path = target
        if let q = path.firstIndex(of: "?") { path = String(path[..<q]) }
        if let h = path.firstIndex(of: "#") { path = String(path[..<h]) }
        path = path.removingPercentEncoding ?? path
        while path.hasPrefix("/") { path.removeFirst() }
        if path.isEmpty { path = "index.html" }
        if path.hasSuffix("/") { path += "index.html" }
        if path.contains("..") { return nil }

        var url = root.appendingPathComponent(path)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            url = url.appendingPathComponent("index.html")
        }
        let std = url.standardizedFileURL
        guard std.path.hasPrefix(root.path) else { return nil }
        guard FileManager.default.fileExists(atPath: std.path) else { return nil }
        return std
    }

    static func mimeType(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js": return "application/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "svg": return "image/svg+xml"
        case "ogg": return "audio/ogg"
        case "m4a": return "audio/mp4"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "mp4": return "video/mp4"
        case "webm": return "video/webm"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "ttf": return "font/ttf"
        case "otf": return "font/otf"
        case "wasm": return "application/wasm"
        case "txt": return "text/plain; charset=utf-8"
        default: return "application/octet-stream"
        }
    }
}
