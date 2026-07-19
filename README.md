# SmartDNS on Alpine (静态二进制)

## 说明

- 基础镜像：`alpine:3.20`
- SmartDNS 采用官方发布的**静态编译二进制**（`smartdns-x86_64`），无 libc 依赖，
  直接从 GitHub Releases 的 `latest/download` 别名获取，始终是最新版本，
  无需在 Dockerfile 里维护具体版本号。
- 配置目录 `/etc/smartdns` 直接映射宿主机目录（`docker run -v` 或 compose `volumes`）。
- 端口 53/udp、53/tcp 直接映射到宿主机。
- 首次运行时如果挂载的宿主机目录是空的，容器会自动用官方默认配置初始化
  `/etc/smartdns/smartdns.conf`，方便你之后直接在宿主机上编辑。

## 构建 / 更新镜像（推荐用 build.sh）

日常构建、以及后续升级 smartdns 版本，都用 `build.sh` 即可，不用手敲 docker 命令：

```bash
chmod +x build.sh

# 首次构建（默认 x86_64，镜像标签 smartdns:alpine）
./build.sh

# 后续更新：重新拉取最新的 smartdns 静态二进制并重建镜像
# （脚本默认 --no-cache --pull，保证拿到的是当前最新 Release）
./build.sh

# 如果容器正在运行，构建完成后脚本会自动 docker rm -f 并重新 docker run 同名容器
```

脚本会做的事：

1. 记录旧镜像里 `smartdns -v` 报告的版本号（如果镜像已存在）。
2. `docker build --no-cache --pull` 重新下载最新静态二进制、重建镜像。
3. 用新镜像里的 `smartdns -v` 输出再打一个版本号 tag，例如 `smartdns:Release48.2`，
   方便你回滚到某个历史版本（`docker run ... smartdns:Release48.1`）。
4. 如果版本号和构建前一致，跳过容器重启（避免无意义中断服务）。
5. 如果版本变化了，且存在同名容器（默认 `smartdns`），自动 `docker rm -f` + `docker run` 重启。

常用参数：

```bash
./build.sh --arch aarch64          # 树莓派 / ARM64 服务器
./build.sh --arch arm              # 32位 ARM
./build.sh --name mydns            # 容器名不是默认的 smartdns 时指定
./build.sh --tag smartdns:test     # 自定义镜像 repo:tag
./build.sh --pin Release48.1       # 固定到指定 Release，而不是始终追 latest
./build.sh --no-restart            # 只重建镜像，不动正在运行的容器
./build.sh --cache                 # 允许用 Docker 缓存（不推荐，可能拿不到最新版本）
./build.sh --help                  # 查看帮助
```

也可以不用脚本，手动构建：

```bash
docker build -t smartdns:alpine .

# 指定架构
docker build --build-arg SMARTDNS_ARCH=aarch64 -t smartdns:alpine .
```

可选架构对应 GitHub Release 里的资产名后缀：`x86_64`、`x86`、`aarch64`、`arm`、`mips`、`mipsel`。

## 运行

首次运行建议直接用脚本，会自动创建同名容器（默认容器名 `smartdns`，挂载 `./etc/smartdns`）：

```bash
mkdir -p ./etc/smartdns
./build.sh
```

也可以手动运行：

```bash
mkdir -p ./etc/smartdns

docker run -d \
  --name smartdns \
  --restart unless-stopped \
  -p 53:53/udp \
  -p 53:53/tcp \
  -v $(pwd)/etc/smartdns:/etc/smartdns \
  smartdns:alpine
```

首次启动后，宿主机的 `./etc/smartdns/smartdns.conf` 会被自动生成，
之后编辑该文件并 `docker restart smartdns` 即可生效（改配置不需要重新构建镜像）。

也可以直接用 docker-compose：

```bash
docker compose up -d --build
```

## 验证

```bash
docker logs -f smartdns
dig @127.0.0.1 www.example.com
```

## 注意事项

1. 宿主机 53 端口不能被占用（Ubuntu/Debian 上常见的 `systemd-resolved` 会占用 53 端口，
   需要先关闭或修改其监听端口）。
2. 如果需要在容器内使用 DoH/DoT 上游，镜像已包含 `ca-certificates`，证书校验不受影响。
3. 如需固定版本而不是始终追最新版，可在构建时传入
   `--build-arg SMARTDNS_BASE_URL=https://github.com/pymumu/smartdns/releases/download/Release48.2`
   指定具体的 Release 标签。

## 从 Docker 迁移到 Podman

Dockerfile、`docker-compose.yml`、`entrypoint.sh` 都**不需要改**，Podman 原生兼容 Dockerfile 语法和
docker CLI 的绝大多数子命令。`build.sh` 已经支持自动探测 `docker` / `podman`（优先 podman），
也可以用 `--engine` 或环境变量 `CONTAINER_ENGINE` 强制指定：

```bash
./build.sh --engine podman
# 或
CONTAINER_ENGINE=podman ./build.sh
```

只有以下几点是 Podman 特有、需要注意的差异：

### 1. 53 端口是特权端口（rootless 场景）

Docker 的 dockerd 本身以 root 运行，容器绑定 53 端口没有问题。
Podman **rootless**（普通用户运行）模式下，容器进程实际上是当前用户的子进程，
默认无法绑定 1024 以下端口，会报 `bind: permission denied`。三选一：

```bash
# 方案一：放开非特权端口下限到 53（一次性，重启失效，需写入 /etc/sysctl.d/ 持久化）
sudo sysctl -w net.ipv4.ip_unprivileged_port_start=53

# 方案二：直接用 root / sudo 运行 podman（即 rootful podman，行为最接近 docker）
sudo ./build.sh
sudo podman run -d --name smartdns -p 53:53/udp -p 53:53/tcp -v $(pwd)/etc/smartdns:/etc/smartdns smartdns:alpine

# 方案三：容器内绑定高位端口，再用 iptables/firewalld 做端口转发到 53（更复杂，不推荐用于单机场景）
```

`build.sh` 在 rootless 模式下会自动检测 `net.ipv4.ip_unprivileged_port_start` 并给出提示。
**如果就是单机跑 DNS 服务，最省心的做法是直接用 rootful podman（加 sudo）**，和用 docker 的体验基本一致。

### 2. SELinux 卷标签（Fedora / RHEL / CentOS 等）

这些发行版默认开启 SELinux，容器内进程访问 bind mount 的宿主机目录会被拒绝，
需要在挂载时加 `:Z`（本容器独占该目录）或 `:z`（可与其他容器共享）标签：

```bash
./build.sh --selinux
# 等价于把 -v ./etc/smartdns:/etc/smartdns 变成 -v ./etc/smartdns:/etc/smartdns:Z
```

`docker-compose.yml` / Quadlet 文件里同理，把 volume 路径写成 `./etc/smartdns:/etc/smartdns:Z`。

### 3. 开机自启 / 崩溃自动重启

Docker 靠常驻的 `dockerd` 实现 `--restart unless-stopped`。Podman 没有常驻 daemon，
`--restart` 参数本身能用，但容器崩溃后**需要 systemd 来触发重启逻辑，开机也需要 systemd 拉起**。
仓库里附带了一个 Quadlet 单元文件 `smartdns.container`（Podman 4.4+/5.x 官方推荐方式），
把里面 `Volume=` 的路径改成你自己的绝对路径后：

```bash
# 系统级（rootful，推荐，因为要监听53端口）
sudo cp smartdns.container /etc/containers/systemd/
sudo systemctl daemon-reload
sudo systemctl enable --now smartdns.service
```

或者继续用 `build.sh` 手动重启也完全没问题，Quadlet 只是让"开机自启 + 崩溃自愈"这件事更省心，
不是必须的。

### 4. docker-compose.yml

Podman 4.x+ 自带 `podman compose` 子命令（底层调用 `podman-compose` 或兼容层），
可以直接复用现有的 `docker-compose.yml`：

```bash
podman compose up -d --build
```

如果 `podman compose` 不可用，装一下 `podman-compose`（`pip install podman-compose` 或发行版包管理器），
用法完全一样。
