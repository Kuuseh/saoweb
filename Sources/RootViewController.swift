import UIKit
import WebKit

final class RootViewController: UIViewController {

    private var server: LocalServer?
    private var webView: WKWebView?

    private let statusLabel = UILabel()
    private let urlField = UITextField()
    private let actionButton = UIButton(type: .system)
    private let progressBar = UIProgressView(progressViewStyle: .default)
    private let hintLabel = UILabel()

    private var mirror: Mirror?
    private var didStartGame = false
    private var saveImportStarted = false
    private var lastImportReport = ""
    private var diagnosticLabel: UILabel?
    private var presentedDebug: UIViewController?

    // MARK: - 生命周期

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        if gameIndexExists() {
            startGame()
        } else {
            buildSetupUI()
        }
    }

    // MARK: - 路径

    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var gameRoot: URL {
        documentsURL.appendingPathComponent("www", isDirectory: true)
    }

    private var indexURL: URL {
        gameRoot.appendingPathComponent("index.html")
    }

    private func gameIndexExists() -> Bool {
        FileManager.default.fileExists(atPath: indexURL.path)
    }

    // MARK: - 首次配置界面

    private func buildSetupUI() {
        let title = UILabel()
        title.text = "SAO 陷阱Ⅱ"
        title.textColor = .white
        title.font = .boldSystemFont(ofSize: 26)
        title.translatesAutoresizingMaskIntoConstraints = false

        hintLabel.text = "把电脑上的游戏传到 iPhone 上。\n电脑端先运行 lan_server.js，然后在这里填电脑地址。"
        hintLabel.textColor = .lightGray
        hintLabel.font = .systemFont(ofSize: 14)
        hintLabel.numberOfLines = 0
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        urlField.text = UserDefaults.standard.string(forKey: "pcBase") ?? "http://192.168.1.100:8123"
        urlField.textColor = .white
        urlField.backgroundColor = UIColor(white: 0.15, alpha: 1)
        urlField.layer.cornerRadius = 8
        urlField.autocapitalizationType = .none
        urlField.autocorrectionType = .no
        urlField.keyboardType = .URL
        urlField.returnKeyType = .go
        urlField.delegate = self
        urlField.translatesAutoresizingMaskIntoConstraints = false
        urlField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
        urlField.leftViewMode = .always

        actionButton.setTitle("从电脑下载并开始", for: .normal)
        actionButton.titleLabel?.font = .boldSystemFont(ofSize: 17)
        actionButton.addTarget(self, action: #selector(startDownload), for: .touchUpInside)
        actionButton.translatesAutoresizingMaskIntoConstraints = false

        progressBar.progress = 0
        progressBar.isHidden = true
        progressBar.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.text = ""
        statusLabel.textColor = .lightGray
        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.numberOfLines = 2
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(title)
        view.addSubview(hintLabel)
        view.addSubview(urlField)
        view.addSubview(actionButton)
        view.addSubview(progressBar)
        view.addSubview(statusLabel)

        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: g.topAnchor, constant: 24),
            title.centerXAnchor.constraint(equalTo: g.centerXAnchor),

            hintLabel.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
            hintLabel.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 40),
            hintLabel.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -40),

            urlField.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 16),
            urlField.leadingAnchor.constraint(equalTo: hintLabel.leadingAnchor),
            urlField.trailingAnchor.constraint(equalTo: hintLabel.trailingAnchor),
            urlField.heightAnchor.constraint(equalToConstant: 36),

            actionButton.topAnchor.constraint(equalTo: urlField.bottomAnchor, constant: 14),
            actionButton.centerXAnchor.constraint(equalTo: g.centerXAnchor),

            progressBar.topAnchor.constraint(equalTo: actionButton.bottomAnchor, constant: 18),
            progressBar.leadingAnchor.constraint(equalTo: urlField.leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: urlField.trailingAnchor),

            statusLabel.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 10),
            statusLabel.leadingAnchor.constraint(equalTo: urlField.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: urlField.trailingAnchor),
        ])
    }

    @objc private func startDownload() {
        view.endEditing(true)
        guard let text = urlField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              let base = URL(string: text),
              base.host != nil else {
            statusLabel.text = "地址不对，格式应该是 http://电脑IP:8123"
            return
        }
        UserDefaults.standard.set(text, forKey: "pcBase")

        actionButton.isEnabled = false
        progressBar.isHidden = false
        statusLabel.text = "正在获取文件清单…"

        let m = Mirror(remoteBase: base, destination: gameRoot)
        self.mirror = m

        m.start(progress: { [weak self] done, total, current in
            guard let self = self else { return }
            let pct = total > 0 ? Double(done) / Double(total) : 0
            self.progressBar.setProgress(Float(pct), animated: false)
            let gb = 1024.0 * 1024.0 * 1024.0
            self.statusLabel.text = String(format: "%.2f / %.2f GB   %@",
                                           Double(done) / gb, Double(total) / gb,
                                           String(current.suffix(40)))
        }, completion: { [weak self] failed, samples in
            guard let self = self else { return }
            if failed == 0 {
                self.statusLabel.text = "下载完成，正在启动…"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.startGame() }
            } else if failed < 0 {
                self.statusLabel.text = "连不上电脑。错误码 \(samples.first ?? "?")。检查：同一 Wi-Fi？地址对不对？"
                self.actionButton.isEnabled = true
            } else {
                self.statusLabel.numberOfLines = 8
                self.statusLabel.text = "有 \(failed) 个文件失败：\n" + samples.joined(separator: "\n")
                self.actionButton.isEnabled = true
            }
        })
    }

    // MARK: - 游戏

    private func startGame() {
        guard !didStartGame else { return }
        guard gameIndexExists() else {
            if actionButton.superview == nil { buildSetupUI() }
            statusLabel.text = "还没有游戏文件"
            return
        }
        didStartGame = true

        // 清掉配置界面
        for sub in view.subviews { sub.removeFromSuperview() }

        let srv = LocalServer(root: gameRoot)
        guard let port = srv.start(preferred: 8123) else {
            let label = UILabel()
            label.text = "本地服务启动失败"
            label.textColor = .white
            label.frame = view.bounds
            label.textAlignment = .center
            view.addSubview(label)
            return
        }
        self.server = srv

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.suppressesIncrementalRendering = false

        let web = WKWebView(frame: view.bounds, configuration: config)
        web.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        web.backgroundColor = .black
        web.isOpaque = true
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.navigationDelegate = self
        view.addSubview(web)
        self.webView = web

        addEscapeButton()

        let url = URL(string: "http://127.0.0.1:\(port)/index.html")!
        web.load(URLRequest(url: url))
    }

    /// 调试：404 记录 + localStorage 全部键（用来确认存档有没有写进去）
    @objc private func showDebugLog() {
        guard let srv = server else { return }
        let notFound = srv.recentNotFound()

        let js = """
        (function(){
          try {
            var out = [];
            for (var i = 0; i < localStorage.length; i++) {
              var k = localStorage.key(i);
              var v = localStorage.getItem(k) || '';
              out.push(k + '  (' + v.length + ')');
            }
            out.sort();
            var rep = localStorage.getItem('__sao_import_report') || '（没有导入报告）';
            return rep + '\\n共 ' + out.length + ' 个键\\n' + out.join('\\n');
          } catch (e) { return 'ls error: ' + e.message; }
        })();
        """

        let show: (String) -> Void = { [weak self] lsText in
            guard let self = self else { return }
            var msg = "=== 存档导入 ===\n"
            msg += self.lastImportReport.isEmpty ? "（尚未执行）\n" : self.lastImportReport + "\n"
            msg += "\n=== 404（最近 20 条）===\n"
            msg += notFound.isEmpty ? "无\n" : notFound.joined(separator: "\n") + "\n"
            msg += "\n=== localStorage ===\n" + lsText
            self.showText(title: "诊断", text: msg)
        }

        if let web = webView {
            web.evaluateJavaScript(js) { result, _ in
                show((result as? String) ?? "读取失败")
            }
        } else {
            show("无 webview")
        }
    }

    private func showText(title: String, text: String) {
        let vc = UIViewController()
        vc.view.backgroundColor = .black
        let tv = UITextView(frame: .zero)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.backgroundColor = .black
        tv.textColor = .white
        tv.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.text = text
        tv.isEditable = false
        vc.view.addSubview(tv)

        let close = UIButton(type: .system)
        close.translatesAutoresizingMaskIntoConstraints = false
        close.setTitle("关闭", for: .normal)
        close.titleLabel?.font = .boldSystemFont(ofSize: 17)
        close.addTarget(self, action: #selector(closeDebug), for: .touchUpInside)
        vc.view.addSubview(close)

        NSLayoutConstraint.activate([
            tv.topAnchor.constraint(equalTo: vc.view.safeAreaLayoutGuide.topAnchor, constant: 8),
            tv.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor, constant: 12),
            tv.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor, constant: -12),
            tv.bottomAnchor.constraint(equalTo: close.topAnchor, constant: -8),
            close.centerXAnchor.constraint(equalTo: vc.view.centerXAnchor),
            close.bottomAnchor.constraint(equalTo: vc.view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            close.widthAnchor.constraint(equalToConstant: 120),
            close.heightAnchor.constraint(equalToConstant: 40),
        ])
        vc.modalPresentationStyle = .fullScreen
        presentedDebug = vc
        present(vc, animated: true)
    }

    @objc private func closeDebug() {
        presentedDebug?.dismiss(animated: true)
        presentedDebug = nil
    }

    /// iOS 没有返回键，给个浮动按钮发 ESC（MV 的菜单键）
    private func addEscapeButton() {
        let btn = UIButton(type: .system)
        btn.setTitle("☰", for: .normal)
        btn.setTitleColor(.white, for: .normal)
        btn.backgroundColor = UIColor(white: 0, alpha: 0.35)
        btn.layer.cornerRadius = 20
        btn.frame = CGRect(x: view.bounds.width - 60, y: 12, width: 44, height: 44)
        btn.autoresizingMask = [.flexibleLeftMargin, .flexibleBottomMargin]
        btn.addTarget(self, action: #selector(sendEscape), for: .touchUpInside)
        let lp = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        lp.minimumPressDuration = 0.8
        btn.addGestureRecognizer(lp)
        view.addSubview(btn)

        let dbg = UIButton(type: .system)
        dbg.setTitle("!", for: .normal)
        dbg.setTitleColor(.white, for: .normal)
        dbg.backgroundColor = UIColor(white: 0, alpha: 0.35)
        dbg.layer.cornerRadius = 20
        dbg.frame = CGRect(x: view.bounds.width - 112, y: 12, width: 44, height: 44)
        dbg.autoresizingMask = [.flexibleLeftMargin, .flexibleBottomMargin]
        dbg.addTarget(self, action: #selector(showDebugLog), for: .touchUpInside)
        view.addSubview(dbg)
    }

    /// 长按 ☰ = 维护菜单（校验修复 / 全部重下）
    @objc private func handleLongPress(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        let sheet = UIAlertController(title: "维护",
                                      message: "校验并修复：只补下缺失或大小不对的文件。\n全部重下：删掉现有数据重新拉 9 GB。",
                                      preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "校验并修复", style: .default) { [weak self] _ in
            self?.enterRepair(deleteAll: false)
        })
        sheet.addAction(UIAlertAction(title: "全部重下", style: .destructive) { [weak self] _ in
            self?.enterRepair(deleteAll: true)
        })
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.width - 60, y: 12, width: 44, height: 44)
        }
        present(sheet, animated: true)
    }

    private func enterRepair(deleteAll: Bool) {
        server?.stop()
        server = nil
        webView?.removeFromSuperview()
        webView = nil
        didStartGame = false

        if deleteAll {
            try? FileManager.default.removeItem(at: gameRoot)
        }

        for sub in view.subviews { sub.removeFromSuperview() }
        buildSetupUI()
        if deleteAll {
            statusLabel.text = "已清空，点下方按钮重新下载"
        } else {
            statusLabel.text = "点下方按钮开始校验，只补缺失的文件"
        }
        actionButton.isEnabled = true
    }

    @objc private func sendEscape() {
        let js = """
        (function(){
          function k(t){
            var e=new KeyboardEvent(t,{bubbles:true,cancelable:true});
            try{
              Object.defineProperty(e,'keyCode',{get:function(){return 27}});
              Object.defineProperty(e,'which',{get:function(){return 27}});
            }catch(x){}
            document.dispatchEvent(e);
          }
          k('keydown'); setTimeout(function(){k('keyup');},50);
        })();
        """
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }
}

extension RootViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        startDownload()
        return true
    }
}

// MARK: - 存档导入
//
// 游戏是 MV 的浏览器模式，存档存在 localStorage（键名 "RPG file1" 这种）。
// 而 www/save/*.rpgsave 这套文件只在 PC 的 NW.js 模式下才被读取，
// 所以在手机上 CONTINUE 列表是空的。这里在页面加载后把文件读进 localStorage。

extension RootViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        importSavesIfNeeded(webView)
    }

    private func importSavesIfNeeded(_ web: WKWebView) {
        // 索引每次启动都要写一次：游戏 boot 时可能把 RPG Global 覆盖成空数组，
        // 只做首次导入会在页面重载后被跳过，导致索引丢失。
        guard !saveImportStarted else { return }
        saveImportStarted = true
        performSaveImport(web)
    }

    private func performSaveImport(_ web: WKWebView) {
        // 索引随包携带：不依赖 App 是否下载过 /save/__global.txt，也不依赖页面的 LZString。
        var bundledIndex = "'no-bundled-index'"
        if let url = Bundle.main.url(forResource: "save_global", withExtension: "txt"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                bundledIndex = jsStringLiteral(trimmed)
            }
        }

        guard let url = Bundle.main.url(forResource: "save_import", withExtension: "js"),
              let script = try? String(contentsOf: url, encoding: .utf8) else {
            NSLog("save import: Resources/save_import.js missing in bundle")
            lastImportReport = "save_import.js 未打进包"
            return
        }

        web.evaluateJavaScript(script) { [weak self] _, injectError in
            if let injectError = injectError {
                NSLog("save import inject error: \(injectError)")
                self?.lastImportReport = "注入失败: \(injectError.localizedDescription)"
                return
            }

            let runner = """
            (function(){
              if (!window.__saoImportRun) return 'no-runner';
              var done = function(report){
                try { localStorage.setItem('__sao_import_report', report); } catch (e) {}
                try { sessionStorage.setItem('sao_import_session','1'); } catch (e) {}
                return report;
              };
              return window.__saoImportRun().then(function(r){
                var o;
                try { o = JSON.parse(r); } catch (e) { o = { errors: ['bad report'] }; }
                var wrote = false;
                try {
                  if (localStorage.getItem('RPG Global') !== \(bundledIndex)) {
                    localStorage.setItem('RPG Global', \(bundledIndex));
                    wrote = true;
                  }
                } catch (e) {
                  (o.errors = o.errors || []).push('index: ' + e.message);
                }
                o.bundledIndexWritten = wrote;
                var report = JSON.stringify(o);
                done(report);
                if (wrote || o.imported > 0) { location.reload(); }
                return report;
              })['catch'](function(e){
                return done(JSON.stringify({ errors: ['exception: ' + e.message] }));
              });
            })();
            """
            web.evaluateJavaScript(runner) { [weak self] result, error in
                let text = (result as? String) ?? "（异步执行中）"
                NSLog("save import -> \(text) \(String(describing: error))")
                self?.lastImportReport = text
                self?.runSaveDiagnostics(web)
            }
        }
    }

    /// 关键状态自检：直接显示在屏幕上，不依赖长按面板
    private func runSaveDiagnostics(_ web: WKWebView) {
        let js = """
        (function(){
          var out = {};
          try { out.globalLen = (localStorage.getItem('RPG Global') || '').length; } catch (e) { out.globalLen = -1; }
          try { out.file1Len = (localStorage.getItem('RPG File1') || '').length; } catch (e) { out.file1Len = -1; }
          try { out.head = (localStorage.getItem('RPG Global') || '').slice(0, 24); } catch (e) { out.head = 'err'; }
          try {
            if (typeof StorageManager !== 'undefined' && StorageManager.webStorageKey) {
              out.key0 = String(StorageManager.webStorageKey(0));
              out.keyM1 = String(StorageManager.webStorageKey(-1));
            }
          } catch (e) { out.key0 = 'err'; }
          try {
            if (typeof StorageManager !== 'undefined' && StorageManager.load) {
              var raw = StorageManager.load(0);
              out.rawType = (raw === null ? 'null' : typeof raw);
              if (typeof raw === 'string') {
                out.rawLen = raw.length;
                var parsed = JSON.parse(raw);
                out.parsedLen = parsed ? parsed.length : -1;
                out.parsedFilled = parsed ? parsed.filter(function(x){return !!x;}).length : -1;
              }
            }
          } catch (e) { out.loadErr = e.message; }
          try {
            if (typeof DataManager !== 'undefined') {
              DataManager.loadGlobalInfo();
              var gi = DataManager._globalInfo || [];
              out.giLen = gi.length;
              out.giFilled = gi.filter(function(x){ return !!x; }).length;
              out.anySave = String(DataManager.isAnySavefileExists());
              out.maxFiles = String(DataManager.maxSavefiles());
            }
          } catch (e) { out.dmErr = e.message; }
          return JSON.stringify(out);
        })();
        """
        web.evaluateJavaScript(js) { [weak self] result, error in
            guard let self = self else { return }
            let text = (result as? String) ?? "诊断失败: \(String(describing: error))"
            NSLog("save diagnostics -> \(text)")
            self.lastImportReport += "\n[自检] " + text
            self.showDiagnosticOverlay(text)
        }
    }

    private func showDiagnosticOverlay(_ text: String) {
        guard let web = webView else { return }
        diagnosticLabel?.removeFromSuperview()
        let label = UILabel()
        label.numberOfLines = 0
        label.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        label.text = "存档自检\n" + text
        label.translatesAutoresizingMaskIntoConstraints = false
        label.layer.cornerRadius = 6
        label.layer.masksToBounds = true
        web.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: web.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: web.trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: web.safeAreaLayoutGuide.topAnchor, constant: 40),
        ])
        diagnosticLabel = label
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak label] in
            label?.removeFromSuperview()
        }
    }

    /// 把任意文本转成安全的 JS 字符串字面量
    private func jsStringLiteral(_ s: String) -> String {        var out = "\""
        for ch in s.unicodeScalars {
            switch ch {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if ch.value < 0x20 || ch.value > 0x7E {
                    out += String(format: "\\u%04x", ch.value)
                } else {
                    out.unicodeScalars.append(ch)
                }
            }
        }
        return out + "\""
    }
}
