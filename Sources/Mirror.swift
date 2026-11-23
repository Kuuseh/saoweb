import Foundation

/// 从电脑上的局域网服务把整个游戏目录镜像到本机 Documents/www。
/// 服务器就是仓库里的 lan_server.js，文件名清单由 make_filelist.py 生成。
final class Mirror {

    struct Entry {
        let path: String
        let size: Int64
    }

    private let base: URL
    private let dest: URL
    private let session: URLSession
    private let stateQueue = DispatchQueue(label: "saoweb.mirror")

    private var entries: [Entry] = []
    private var nextIndex = 0
    private var active = 0
    private var totalBytes: Int64 = 0
    private var doneBytes: Int64 = 0
    private var failed: [String] = []
    private var finished = false

    private var progressHandler: ((Int64, Int64, String) -> Void)?
    private var completionHandler: ((Int, [String]) -> Void)?

    private let maxConcurrent = 4

    init(remoteBase: URL, destination: URL) {
        self.base = remoteBase
        self.dest = destination
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.httpMaximumConnectionsPerHost = 4
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: cfg)
    }

    // MARK: - 入口

    func start(progress: @escaping (Int64, Int64, String) -> Void,
               completion: @escaping (Int, [String]) -> Void) {
        self.progressHandler = progress
        self.completionHandler = completion
        fetchList { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let list):
                self.prepare(list)
            case .failure(let err):
                NSLog("filelist failed: \(err)")
                DispatchQueue.main.async { completion(-1, [(err as NSError).code.description]) }
            }
        }
    }

    // MARK: - 获取清单

    private func fetchList(completion: @escaping (Result<[Entry], Error>) -> Void) {
        let url = base.appendingPathComponent("filelist.json")
        let task = session.dataTask(with: url) { data, _, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(NSError(domain: "mirror", code: 1, userInfo: [NSLocalizedDescriptionKey: "empty filelist"])))
                return
            }
            do {
                let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let raw = (obj?["files"] as? [[String: Any]]) ?? []
                var list: [Entry] = []
                list.reserveCapacity(raw.count)
                for item in raw {
                    guard let p = item["p"] as? String, let s = item["s"] as? NSNumber else { continue }
                    list.append(Entry(path: p, size: s.int64Value))
                }
                if list.isEmpty {
                    completion(.failure(NSError(domain: "mirror", code: 2, userInfo: [NSLocalizedDescriptionKey: "filelist 是空的"])))
                } else {
                    completion(.success(list))
                }
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }

    // MARK: - 计算待下载部分

    private func prepare(_ list: [Entry]) {
        var pending: [Entry] = []
        var already: Int64 = 0
        let fm = FileManager.default
        for e in list {
            let url = dest.appendingPathComponent(e.path)
            if let attrs = try? fm.attributesOfItem(atPath: url.path),
               let size = (attrs[.size] as? NSNumber)?.int64Value,
               size == e.size {
                already += e.size
                continue
            }
            pending.append(e)
        }

        stateQueue.async {
            self.entries = pending
            self.totalBytes = pending.reduce(into: Int64(0)) { $0 += $1.size }
            self.doneBytes = 0
            let total = self.totalBytes
            NSLog("mirror: \(pending.count) files pending, \(total) bytes (already \(already))")
            DispatchQueue.main.async { self.progressHandler?(0, total, "") }
            if pending.isEmpty {
                self.finishIfDone()
            } else {
                self.pump()
            }
        }
    }

    // MARK: - 并发下载

    private func pump() {
        while active < maxConcurrent && nextIndex < entries.count {
            let entry = entries[nextIndex]
            nextIndex += 1
            active += 1
            downloadOne(entry)
        }
    }

    private func downloadOne(_ entry: Entry) {
        guard let url = Mirror.makeURL(base: base, path: entry.path) else {
            stateQueue.async {
                self.failed.append(entry.path)
                self.active -= 1
                self.pump()
                self.finishIfDone()
            }
            return
        }

        let task = session.downloadTask(with: url) { [weak self] tmp, response, error in
            guard let self = self else { return }
            var ok = false
            var reason = ""
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                reason = "HTTP \(http.statusCode)"
            } else if let error = error {
                reason = (error as NSError).code.description
            } else if let tmp = tmp {
                let target = self.dest.appendingPathComponent(entry.path)
                do {
                    try FileManager.default.createDirectory(
                        at: target.deletingLastPathComponent(),
                        withIntermediateDirectories: true)
                    if FileManager.default.fileExists(atPath: target.path) {
                        try FileManager.default.removeItem(at: target)
                    }
                    try FileManager.default.moveItem(at: tmp, to: target)
                    let attrs = try FileManager.default.attributesOfItem(atPath: target.path)
                    let size = (attrs[.size] as? NSNumber)?.int64Value ?? -1
                    if size == entry.size {
                        ok = true
                    } else {
                        reason = "size \(size)≠\(entry.size)"
                    }
                } catch {
                    reason = "write"
                    NSLog("move failed \(entry.path): \(error)")
                }
            } else {
                reason = "empty"
            }
            self.stateQueue.async {
                self.active -= 1
                if ok {
                    self.doneBytes += entry.size
                } else {
                    self.failed.append(entry.path + "  [" + reason + "]")
                }
                let done = self.doneBytes
                let total = self.totalBytes
                DispatchQueue.main.async {
                    self.progressHandler?(done, total, entry.path)
                }
                self.pump()
                self.finishIfDone()
            }
        }
        task.resume()
    }

    private func finishIfDone() {
        guard !finished, nextIndex >= entries.count, active == 0 else { return }
        finished = true
        let failCount = failed.count
        let sample = Array(failed.prefix(5))
        NSLog("mirror done, failed=\(failCount) \(sample.joined(separator: " | "))")
        DispatchQueue.main.async {
            self.completionHandler?(failCount, sample)
        }
    }

    /// 拼接下载地址。
    /// 注意：URLComponents.path 的 setter 自己会做百分号编码，
    /// 这里绝对不能再手动 encode 一遍，否则会变成 %2520 → 服务器 404。
    static func makeURL(base: URL, path: String) -> URL? {
        guard var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return nil
        }
        var prefix = comps.path
        while prefix.hasSuffix("/") { prefix.removeLast() }
        comps.path = prefix + "/" + path
        return comps.url
    }
}
