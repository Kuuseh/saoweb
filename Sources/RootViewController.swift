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
        }, completion: { [weak self] failed, _ in
            guard let self = self else { return }
            if failed == 0 {
                self.statusLabel.text = "下载完成，正在启动…"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.startGame() }
            } else if failed < 0 {
                self.statusLabel.text = "连不上电脑。检查：同一 Wi-Fi？地址对不对？电脑防火墙放行了没？"
                self.actionButton.isEnabled = true
            } else {
                self.statusLabel.text = "有 \(failed) 个文件没下下来，再点一次会只补缺失的文件"
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
        guard let port = srv.start() else {
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
        view.addSubview(web)
        self.webView = web

        addEscapeButton()

        let url = URL(string: "http://127.0.0.1:\(port)/index.html")!
        web.load(URLRequest(url: url))
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
        view.addSubview(btn)
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
