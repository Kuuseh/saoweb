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
    private var completionHandler: ((Int) -> Void)?

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
               completion: @escaping (Int, Int) -> Void) {
        self.progressHandler = progress
        self.completionHandler = { failedCount in
            completion(failedCount, 0)
        }
        fetchList { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let list):
                self.prepare(list)
            case .failure(let err):
                NSLog("filelist failed: \(err)")
                DispatchQueue.main.async { completion(-1, 0) }
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
        guard let url = buildURL(for: entry.path) else {
            stateQueue.async {
                self.failed.append(entry.path)
                self.active -= 1
                self.pump()
                self.finishIfDone()
            }
            return
        }

        let task = session.downloadTask(with: url) { [weak self] tmp, _, error in
            guard let self = self else { return }
            var ok = false
            if error == nil, let tmp = tmp {
                let target = self.dest.appendingPathComponent(entry.path)
                do {
                    try FileManager.default.createDirectory(
                        at: target.deletingLastPathComponent(),
                        withIntermediateDirectories: true)
                    if FileManager.default.fileExists(atPath: target.path) {
                        try FileManager.default.removeItem(at: target)
                    }
                    try FileManager.default.moveItem(at: tmp, to: target)
                    ok = true
                } catch {
                    NSLog("move failed \(entry.path): \(error)")
                }
            }
            self.stateQueue.async {
                self.active -= 1
                if ok {
                    self.doneBytes += entry.size
                } else {
                    self.failed.append(entry.path)
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
        let sample = failed.prefix(5).joined(separator: ", ")
        NSLog("mirror done, failed=\(failCount) \(sample)")
        DispatchQueue.main.async {
            self.completionHandler?(failCount)
        }
    }

    private func buildURL(for path: String) -> URL? {
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)
        let encoded = path.split(separator: "/").map { seg -> String in
            String(seg).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(seg)
        }.joined(separator: "/")
        comps?.path = (comps?.path ?? "") + "/" + encoded
        return comps?.url
    }
}
