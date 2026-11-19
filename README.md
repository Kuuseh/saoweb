# SAOWeb — RPG Maker MV 游戏在 iPhone 上的运行壳

把 PC 上的 RPG Maker MV 游戏搬到 iPhone 上玩的外壳 App。

游戏本体不出现在 App 里：App 内置一个只读 HTTP 服务，从自己的 Documents 目录提供游戏文件，
WKWebView 从 `http://127.0.0.1:<port>` 加载 —— 这样 localStorage（存档）、XHR 资源加载都正常。

## 为什么不能像安卓那样直接一个 APK

iOS 只装签名过的 IPA，没有「打包成安装包」这回事。这里走的是：

```
GitHub Actions（macOS 机器）编译 → 未签名 IPA → 你在 Windows 上用 Sideloadly + Apple ID 签名 → 安装
```

免费 Apple ID 签的证书 **7 天过期**，到期要用 Sideloadly 覆盖安装重签一次。

## 构建（GitHub Actions，不需要 Mac）

1. 注册/登录 GitHub
2. 新建仓库，比如 `saoweb`，**选 Public**（Public 仓库的 Actions 完全免费；Private 会消耗额度）
3. 把本目录里的所有内容传上去，注意 `.github` 是隐藏目录，别漏了
4. 打开仓库 → **Actions** → 左边选 `build-ipa` → **Run workflow**
5. 等 3～6 分钟，进这次运行，底部 **Artifacts** 下载 `SAOWeb-unsigned-ipa`
6. 解压得到 `SAOWeb-unsigned.ipa`

如果构建失败，把 Actions 日志里 `Build (unsigned)` 那一段发我。

## 签名安装（Windows）

1. 装 [Sideloadly](https://sideloadly.io/)（Windows 版）
2. 电脑装 iTunes 或 Apple Devices（Sideloadly 需要它提供驱动）
3. iPhone 插线，信任电脑
4. Sideloadly 里：
   - IPA 选刚下载的 `SAOWeb-unsigned.ipa`
   - Apple ID 填你的（免费账号就行）
   - 点 Start，输入密码，等进度条走完
5. 手机上：设置 → 通用 → VPN与设备管理 → 信任你的开发者证书
6. 打开 App（图标叫「SAO 陷阱」）

## 传游戏文件（9.1 GB）

不需要数据线，走局域网：

1. 电脑上双击 `tools/start_pc_server.bat`（要先装 Node.js）
   - 如果 Windows 弹防火墙提示，**允许**，并勾上「公用网络」
   - 看窗口里打印的地址，通常就是 `http://192.168.x.x:8123`
2. iPhone 和电脑连**同一个 Wi-Fi**
3. 打开 App，地址栏填 `http://电脑IP:8123`，点「从电脑下载并开始」
4. 下载进度到 100% 自动进游戏

下载是**可断点续传**的：中途断了，再点一次只会补缺失的文件（按文件大小比对）。

## 操作

- 横屏全屏，无状态栏
- 点按/拖动 = 鼠标左键（MV 原生支持触屏行走）
- 右上角 **☰** 按钮 = ESC（游戏菜单）
- iOS 没有返回键，退出用上滑手势

## 已知限制

- **免费证书 7 天失效**：到期 App 打不开，用 Sideloadly 覆盖安装重签。**不要先卸载**，卸载会清掉 9 GB 游戏数据和存档
- **内存**：iPhone 上 WKWebView 内存限制比 iPad 严，大场景可能闪退；iPad 更稳
- **音频**：iOS 要求先点一下屏幕才能出声
- **首次启动慢**：要先读 6 万条文件清单

## 目录

```
project.yml                  XcodeGen 工程描述
Sources/
  AppDelegate.swift          入口
  RootViewController.swift   首次配置界面 + WKWebView + 悬浮 ESC 按钮
  LocalServer.swift          极简 HTTP 服务（Range / MIME / 路径穿越防护）
  Mirror.swift               从电脑拉取游戏文件（4 并发 + 断点续传）
Resources/Info.plist         文件共享、横屏、ATS、局域网权限
tools/
  lan_server.js              电脑端静态服务器
  start_pc_server.bat        一键启动
  make_filelist.py           生成 filelist.json（App 靠它知道要下哪些文件）
.github/workflows/ios.yml    云编译
```

## 本地修改后重新构建

改完代码推到 GitHub，Actions 会自动跑（push 到 main 触发），也可以手动 Run workflow。
