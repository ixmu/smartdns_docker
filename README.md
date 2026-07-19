# SmartDNS on Alpine (Podman)

## 说明

- 基础镜像：`alpine:3.20`
- SmartDNS 采用官方发布的**静态编译二进制**（`smartdns-x86_64`），无 libc 依赖，
  直接从 GitHub Releases 的 `latest/download` 别名获取，始终是最新版本，
  无需在 Containerfile 里维护具体版本号。
- 配置目录 `/etc/smartdns` 直接映射宿主机目录（`-v` 或 compose `volumes`）。
- 端口 53/udp、53/tcp 直接映射到宿主机。
- 首次运行时如果挂载的宿主机目录是空的，容器会自动用官方默认配置初始化
  `/etc/smartdns/smartdns.conf`，方便你之后直接在宿主机上编辑。

## 文件说明

| 文件 | 作用 |
|---|---|
| `Containerfile` | 镜像定义（Podman 惯用命名，等价于 Dockerfile） |
| `entrypoint.sh` | 容器启动脚本，首次运行自动初始化配置 |
| `build.sh` | 构建/更新脚本，日常只用这个就够了 |
| `podman-compose.yml` | 供 `podman compose` / `podman-compose` 使用 |
| `smartdns.container` | Quadlet 单元文件，交给 systemd 管理开机自启/崩溃重启 |

## 关于 53 端口（特权端口）

DNS 服务要监听 53 端口，**rootless podman 默认无法绑定 1024 以下端口**，会报
`bind: permission denied`。三选一：

```bash
# 方案一：放开非特权端口下限到 53（一次性生效，重启失效，需写入 /etc/sysctl.d/ 持久化）
sudo sysctl -w net.ipv4.ip_unprivileged_port_start=53

# 方案二：直接用 sudo / root 运行（rootful podman，最省心，推荐）
sudo ./build.sh

# 方案三：容器内绑定高位端口，自行用 iptables/firewalld 转发到 53（更复杂，不推荐单机场景）
```

**单机跑 DNS 服务的话，最省心的做法就是全程加 `sudo`（rootful podman）**，
下面的示例默认按这个思路写。

## 构建 / 更新镜像：build.sh

日常构建、以及后续升级 smartdns 版本，都用 `build.sh` 即可：

```bash
chmod +x build.sh

# 首次构建（默认 x86_64，镜像标签 smartdns:alpine）
sudo ./build.sh

# 后续更新：重新拉取最新的 smartdns 静态二进制并重建镜像
# （脚本默认 --no-cache --pull，保证拿到的是当前最新 Release）
sudo ./build.sh
```

脚本会做的事：

1. 记录旧镜像里 `smartdns -v` 报告的版本号（如果镜像已存在）。
2. `podman build --no-cache --pull` 重新下载最新静态二进制、重建镜像。
3. 用新镜像里的 `smartdns -v` 输出再打一个版本号 tag，例如 `smartdns:Release48.2`，
   方便你回滚到某个历史版本（`podman run ... smartdns:Release48.1`）。
4. 如果版本号和构建前一致，跳过容器重启（避免无意义中断服务）。
5. 如果版本变化了，且存在同名容器（默认 `smartdns`），自动 `podman rm -f` + `podman run` 重启。
6. 如果检测到是 rootless podman 且系统未放开 53 端口，会打印警告和解决方法。

常用参数：

```bash
./build.sh --arch aarch64          # 树莓派 / ARM64 服务器
./build.sh --arch arm              # 32位 ARM
./build.sh --name mydns            # 容器名不是默认的 smartdns 时指定
./build.sh --tag smartdns:test     # 自定义镜像 repo:tag
./build.sh --pin Release48.1       # 固定到指定 Release，而不是始终追 latest
./build.sh --no-restart            # 只重建镜像，不动正在运行的容器
./build.sh --selinux               # 挂载卷加 :Z 标签（Fedora/RHEL/CentOS 等启用 SELinux 的系统）
./build.sh --cache                 # 允许用构建缓存（不推荐，可能拿不到最新版本）
./build.sh --help                  # 查看帮助
```

可选架构对应 GitHub Release 里的资产名后缀：`x86_64`、`x86`、`aarch64`、`arm`、`mips`、`mipsel`。

## 手动运行（不用 build.sh 时）

```bash
mkdir -p ./etc/smartdns

sudo podman build -t smartdns:alpine -f Containerfile .

sudo podman run -d \
  --name smartdns \
  --restart unless-stopped \
  -p 53:53/udp \
  -p 53:53/tcp \
  -v $(pwd)/etc/smartdns:/etc/smartdns \
  smartdns:alpine
```

Fedora/RHEL/CentOS 等 SELinux 系统上，把挂载卷改成 `$(pwd)/etc/smartdns:/etc/smartdns:Z`。

首次启动后，宿主机的 `./etc/smartdns/smartdns.conf` 会被自动生成，
之后编辑该文件并 `podman restart smartdns` 即可生效（改配置不需要重新构建镜像）。

## 用 podman compose

```bash
podman compose -f podman-compose.yml up -d --build
```

如果本机没有 `podman compose` 子命令，装一下 `podman-compose`
（`pip install podman-compose` 或发行版包管理器），用法完全一样。

## 开机自启 / 崩溃自动重启：systemd + Quadlet

Podman 没有像 dockerd 那样的常驻进程，容器崩溃后的自动重启、开机自启都需要交给 systemd。
仓库里的 `smartdns.container` 是 Quadlet 单元文件（Podman 4.4+/5.x 官方推荐方式）：

```bash
# 先把 smartdns.container 里 Volume= 那一行的路径改成本项目实际的绝对路径
sudo cp smartdns.container /etc/containers/systemd/
sudo systemctl daemon-reload
sudo systemctl enable --now smartdns.service

sudo systemctl status smartdns.service
journalctl -u smartdns.service -f
```

之后更新镜像（`sudo ./build.sh`）完成后，`sudo systemctl restart smartdns.service` 即可生效，
不需要手动 `podman rm` / `podman run`。

## 验证

```bash
podman logs -f smartdns
dig @127.0.0.1 www.example.com
```

## 注意事项

1. 宿主机 53 端口不能被占用（Ubuntu/Debian 上常见的 `systemd-resolved` 会占用 53 端口，
   需要先关闭或修改其监听端口）。
2. 如果需要在容器内使用 DoH/DoT 上游，镜像已包含 `ca-certificates`，证书校验不受影响。
3. 如需固定版本而不是始终追最新版，可在构建时传入
   `--build-arg SMARTDNS_BASE_URL=https://github.com/pymumu/smartdns/releases/download/Release48.2`
   指定具体的 Release 标签，或直接用 `build.sh --pin Release48.2`。
