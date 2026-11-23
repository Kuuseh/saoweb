import Foundation

// 把 LocalServer.swift 一起编译成命令行程序，在 macOS runner 上跑。
// 目的：在打包之前验证「本地 HTTP 服务」的真实行为，避免再到手机上试错。

let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("srvcheck-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

func write(_ rel: String, _ text: String) {
    let url = tmp.appendingPathComponent(rel)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? text.data(using: .utf8)?.write(to: url)
}

write("index.html", "<html>mock</html>")
write("js/rpg_core.js", "var RPG={};")
write("img/Special__actionSeq/爱丽丝催眠自慰 (01).png", String(repeating: "x", count: 5000))
write("audio/x.ogg", "OGGDATA")

var failures = 0
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    if ok {
        print("  OK   \(name) \(detail)")
    } else {
        failures += 1
        print("  FAIL \(name) \(detail)")
    }
}

func fetch(_ url: String, method: String = "GET", range: String? = nil) -> (Int, Data) {
    var req = URLRequest(url: URL(string: url)!)
    req.httpMethod = method
    if let r = range { req.setValue(r, forHTTPHeaderField: "Range") }
    var code = -1
    var body = Data()
    let sem = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: req) { data, resp, _ in
        code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        body = data ?? Data()
        sem.signal()
    }.resume()
    _ = sem.wait(timeout: .now() + 10)
    return (code, body)
}

let server = LocalServer(root: tmp)
guard let port = server.start(preferred: 18123) else {
    print("FAIL: server did not start")
    exit(1)
}
print("server on \(port)")

let base = "http://127.0.0.1:\(port)"
check("root", fetch("\(base)/").0 == 200)
check("index.html", fetch("\(base)/index.html").0 == 200)
check("js file", fetch("\(base)/js/rpg_core.js").0 == 200)

var comps = URLComponents()
comps.path = "/img/Special__actionSeq/爱丽丝催眠自慰 (01).png"
let chineseURL = base + (comps.percentEncodedPath)
let chinese = fetch(chineseURL)
check("中文路径", chinese.0 == 200 && chinese.1.count == 5000, "code=\(chinese.0) bytes=\(chinese.1.count)")

let missing = fetch("\(base)/missing.js")
check("404", missing.0 == 404)

let ranged = fetch("\(base)/js/rpg_core.js", range: "bytes=0-3")
check("Range", ranged.0 == 206 && ranged.1.count == 4, "code=\(ranged.0) bytes=\(ranged.1.count)")

let head = fetch("\(base)/index.html", method: "HEAD")
check("HEAD", head.0 == 200)

server.stop()

if failures > 0 {
    print("RESULT: \(failures) failure(s)")
    exit(1)
}
print("RESULT: all passed")
exit(0)
