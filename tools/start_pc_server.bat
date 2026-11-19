@echo off
chcp 65001 >nul
echo 正在启动游戏局域网服务...
echo 手机浏览器/App 里填： http://本机IP:8123
echo 按 Ctrl+C 停止
"C:\Users\fangj\AppData\Local\Programs\nodejs-v24.19.0\node.exe" "%~dp0lan_server.js" "D:\RPGSAO_src\[RPG]SAO~气息遮断魔法的陷阱Ⅱ~verβ9  官方中文\www" 8123
pause
