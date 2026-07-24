# SmartDNS Docker Image

一个本地 DNS 服务器，能够获取最快的网站 IP 以获得最佳上网体验。支持 DoH、DoT 及 DoQ。  
*A local DNS server designed to obtain the fastest website IP for the best Internet experience. Supports DoH, DoT, and DoQ.*

* **源代码 | Source Code**: [pymumu/smartdns](https://github.com/pymumu/smartdns)
* **官方文档 | Document**: [pymumu.github.io/smartdns](https://pymumu.github.io/smartdns)

---

## 💻 支持的架构 | Supported Architectures

* `X86-64` (`linux/amd64`)
* `ARM64` (`linux/arm64`)

---

## 📝 镜像说明 | Image Description

SmartDNS 默认配置文件路径为 `/etc/smartdns`，默认 DNS 服务端口为 `53`，所有的运行日志会自动输出到终端控制台（Standard Output）。

*The default configuration directory for the image is `/etc/smartdns/`, and the default DNS server port is `53`. All logs will be output directly to the terminal.*

---

## 📂 卷映射说明 | Volumes

| 容器内路径 | 说明 | Description |
| :--- | :--- | :--- |
| `/etc/smartdns` | 配置文件目录 | Configuration file directory |
| `/var/lib/smartdns` | WebUI 数据文件目录 | WebUI data directory |

---

## 🔌 端口映射说明 | Ports

| 端口号 | 协议 | 说明 | Description |
| :--- | :--- | :--- | :--- |
| **53** | `UDP` / `TCP` | DNS 服务端口 | DNS Server Port |
| **6080** | `TCP` | WebUI 服务端口 | WebUI Server Port |

---

## ⚙️ 配置说明 | Configuration Instructions

在挂载的宿主机路径中创建配置文件 `/etc/smartdns/smartdns.conf`，并添加以下基础必填配置：  
*Create the `/etc/smartdns/smartdns.conf` file on your host and add the following basic configurations:*

```ini
# 绑定监听端口 / Bind listen port
bind [::]:53

# 上游 DNS 服务器 / Upstream DNS servers
server 8.8.8.8
server 1.1.1.1

# 启用 WebUI 服务 (可选) / Enable WebUI service (Optional)
plugin smartdns_ui.so