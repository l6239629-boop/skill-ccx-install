# CCX 安装故障排查指南

## 1. 浏览器无法访问 http://localhost:3688

### 服务未运行
```bash
# 检查服务是否在运行
launchctl list | grep ccx

# 如果没有任何输出，说明服务未运行，手动启动
launchctl start com.ccx.proxy

# 等待 2 秒后验证
sleep 2 && curl -s -o /dev/null -w "%{http_code}" http://localhost:3688/
# 应返回 200
```

### 端口被占用
```bash
# 检查 3688 端口被哪个进程占用
lsof -i :3688

# 如果被其他程序占用，修改 .env 中的 PORT 为其他值（如 3689）
# 然后重启服务
launchctl stop com.ccx.proxy
launchctl start com.ccx.proxy
```

### 服务启动但立即退出
```bash
# 查看错误日志
cat /tmp/ccx.stderr.log
cat /tmp/ccx.stdout.log

# 查看应用日志
cat "<install-dir>/backend-go/logs/app.log"
```

## 2. 二进制文件无法执行

### "Permission denied"
```bash
chmod +x "<install-dir>/backend-go/ccx"
```

### "Bad CPU type" 或架构错误
下载的二进制架构与 Mac 不匹配：
- Apple Silicon (M1/M2/M3/M4) → 需要 `ccx-darwin-arm64`
- Intel Mac → 需要 `ccx-darwin-amd64`

```bash
# 检查当前二进制架构
file "<install-dir>/backend-go/ccx"
# 正确输出: Mach-O 64-bit executable arm64 (Apple Silicon)
# 或: Mach-O 64-bit executable x86_64 (Intel)
```

### 二进制文件缺失
```bash
# 检查文件是否存在
ls -la "<install-dir>/backend-go/ccx"
# 如果不存在，重新运行安装脚本
```

## 3. 配置问题

### 忘记访问密码
查看 `.env` 文件中的 `PROXY_ACCESS_KEY`：
```bash
grep PROXY_ACCESS_KEY "<install-dir>/backend-go/.env"
```

### 修改配置后不生效
修改 `.env` 后需要重启服务：
```bash
launchctl stop com.ccx.proxy
launchctl start com.ccx.proxy
```

### 渠道配置丢失
检查自动备份：
```bash
ls -la "<install-dir>/backend-go/.config/backups/"
```
备份文件命名格式：`config-YYYY-MM-DDTHH-MM-SS.json`

恢复备份：
```bash
cp "<install-dir>/backend-go/.config/backups/<backup-file>" "<install-dir>/backend-go/.config/config.json"
launchctl stop com.ccx.proxy
launchctl start com.ccx.proxy
```

## 4. LaunchAgent 问题

### 开机不自启
```bash
# 检查 plist 是否存在
ls -la ~/Library/LaunchAgents/com.ccx.proxy.plist

# 重新加载服务
launchctl unload ~/Library/LaunchAgents/com.ccx.proxy.plist
launchctl load ~/Library/LaunchAgents/com.ccx.proxy.plist

# 检查是否已加载
launchctl list | grep ccx
```

### 多个 LaunchAgent 冲突
```bash
# 列出所有已加载的代理
launchctl list

# 如果存在多个 ccx 相关服务，全部卸载后重新加载
launchctl unload ~/Library/LaunchAgents/com.ccx.proxy.plist 2>/dev/null
launchctl load ~/Library/LaunchAgents/com.ccx.proxy.plist
```

## 5. Git 相关问题

### 克隆失败（网络问题）
```bash
# 检查网络连接
ping -c 3 github.com

# 使用代理（如需要）
git config --global http.proxy http://127.0.0.1:7890
git config --global https.proxy http://127.0.0.1:7890
```

### 仓库已存在但损坏
```bash
# 进入安装目录
cd "<install-dir>"

# 尝试修复
git fetch --all
git reset --hard origin/main
```

## 6. 更新问题

### 更新后配置丢失
安装脚本会自动备份 `.env` 和 `.config/`，检查备份：
```bash
# 查找备份文件
find "<install-dir>" -name "*.bak.*" -o -name "*.backup.*" 2>/dev/null
```

### 更新后服务无法启动
可能是新版本有 Breaking Changes，查看更新日志：
```bash
cat "<install-dir>/CHANGELOG.md"
```

## 7. macOS 系统问题

### "ccx" 无法打开，因为无法验证开发者
```bash
# 在"系统设置 > 隐私与安全性"中点击"仍要打开"
# 或使用命令行移除隔离属性
xattr -d com.apple.quarantine "<install-dir>/backend-go/ccx"
```

### 系统报告"ccx"已损坏
```bash
# 重新下载二进制
# 或移除隔离属性后重试
xattr -cr "<install-dir>/backend-go/ccx"
```

## 8. 日志查看速查

| 日志文件 | 用途 |
|---------|------|
| `/tmp/ccx.stdout.log` | CCX 标准输出（启动信息） |
| `/tmp/ccx.stderr.log` | CCX 错误输出 |
| `<install-dir>/backend-go/logs/app.log` | CCX 应用日志（轮转） |
| `<install-dir>/backend-go/.config/metrics.db` | 指标数据库（SQLite） |

## 9. 诊断命令汇总

```bash
# 一键诊断
echo "=== 服务状态 ===" && launchctl list | grep ccx && \
echo "=== 端口监听 ===" && curl -s -o /dev/null -w "HTTP %{http_code}\n" http://localhost:3688/ && \
echo "=== 二进制信息 ===" && file "<install-dir>/backend-go/ccx" && \
echo "=== 配置文件 ===" && ls -la "<install-dir>/backend-go/.env" && \
echo "=== 配置目录 ===" && ls -la "<install-dir>/backend-go/.config/"
```
