#!/bin/sh
# =============================================================
# SmartDNS (Alpine) 构建/更新脚本
# 兼容 Docker 和 Podman —— 自动探测，或用 --engine / CONTAINER_ENGINE 指定
#
# 用途：
#   - 首次构建镜像
#   - 后续更新时重新拉取最新的 smartdns 静态二进制并重建镜像
#   - 自动用 smartdns 自身的版本号打 tag，方便追溯/回滚
#   - 可选：构建完成后自动重启正在运行的容器
#
# 用法：
#   ./build.sh                      # 默认参数构建/更新
#   ./build.sh --engine podman      # 强制使用 podman（默认自动探测，优先 podman）
#   ./build.sh --arch aarch64       # 指定架构
#   ./build.sh --name mydns         # 指定容器名，构建后自动重启该容器
#   ./build.sh --no-restart         # 只构建，不重启容器
#   ./build.sh --tag smartdns:test  # 自定义镜像仓库/标签
#   ./build.sh --pin Release48.1    # 固定到指定 Release 而不是 latest
#   ./build.sh --selinux            # 给挂载卷加 :Z 标签（Fedora/RHEL/CentOS 等启用了 SELinux 的系统）
#
# 环境变量（与命令行参数等价，命令行参数优先级更高）：
#   CONTAINER_ENGINE, SMARTDNS_ARCH, IMAGE_TAG, CONTAINER_NAME, PIN_RELEASE
# =============================================================

set -eu

# ---------- 默认配置 ----------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENGINE="${CONTAINER_ENGINE:-}"
SMARTDNS_ARCH="${SMARTDNS_ARCH:-x86_64}"        # x86_64 / x86 / aarch64 / arm / mips / mipsel
IMAGE_TAG="${IMAGE_TAG:-smartdns:alpine}"
CONTAINER_NAME="${CONTAINER_NAME:-smartdns}"
PIN_RELEASE="${PIN_RELEASE:-}"                  # 例如 Release48.1，留空则始终使用 latest
DO_RESTART=1
NO_CACHE=1
SELINUX_LABEL=0

# ---------- 解析参数 ----------
while [ $# -gt 0 ]; do
    case "$1" in
        --engine)       ENGINE="$2"; shift 2 ;;
        --arch)         SMARTDNS_ARCH="$2"; shift 2 ;;
        --tag)          IMAGE_TAG="$2"; shift 2 ;;
        --name)         CONTAINER_NAME="$2"; shift 2 ;;
        --pin)          PIN_RELEASE="$2"; shift 2 ;;
        --no-restart)   DO_RESTART=0; shift ;;
        --cache)        NO_CACHE=0; shift ;;   # 允许使用构建缓存（不推荐，可能拿不到最新版）
        --selinux)      SELINUX_LABEL=1; shift ;;
        -h|--help)
            sed -n '2,29p' "$0"; exit 0 ;;
        *)
            echo "未知参数: $1" >&2; exit 1 ;;
    esac
done

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$1"; }

# ---------- 探测容器引擎 ----------
if [ -z "$ENGINE" ]; then
    if command -v podman >/dev/null 2>&1; then
        ENGINE=podman
    elif command -v docker >/dev/null 2>&1; then
        ENGINE=docker
    else
        echo "未找到 docker 或 podman，请先安装其中之一。" >&2
        exit 1
    fi
fi
if ! command -v "$ENGINE" >/dev/null 2>&1; then
    echo "指定的引擎 '$ENGINE' 不存在。" >&2
    exit 1
fi
log "使用容器引擎: ${ENGINE}"

# rootless podman 无法绑定 53 端口（<1024 特权端口），检测并提前告警
if [ "$ENGINE" = "podman" ] && [ "$(id -u)" != "0" ]; then
    UNPRIV_START="$(sysctl -n net.ipv4.ip_unprivileged_port_start 2>/dev/null || echo 1024)"
    if [ "$UNPRIV_START" -gt 53 ] 2>/dev/null; then
        log "警告: 当前是 rootless podman，且系统未放开 53 端口的非特权绑定。"
        log "      监听 53 端口会失败，解决办法（任选其一）:"
        log "      1) sudo sysctl -w net.ipv4.ip_unprivileged_port_start=53  (需持久化到 /etc/sysctl.d/)"
        log "      2) 用 sudo/root 运行本脚本 (rootful podman)"
        log "      3) 用 --tag 里的端口改成 >1024 的端口，再自行做端口转发"
    fi
fi

# ---------- 组装 build-arg ----------
BUILD_ARGS="--build-arg SMARTDNS_ARCH=${SMARTDNS_ARCH}"

if [ -n "$PIN_RELEASE" ]; then
    BASE_URL="https://github.com/pymumu/smartdns/releases/download/${PIN_RELEASE}"
    log "固定使用 Release: ${PIN_RELEASE}"
    BUILD_ARGS="${BUILD_ARGS} --build-arg SMARTDNS_BASE_URL=${BASE_URL}"
fi

CACHE_FLAG=""
[ "$NO_CACHE" = "1" ] && CACHE_FLAG="--no-cache --pull"

# ---------- 记录旧版本（如果镜像已存在）----------
OLD_VERSION=""
if "$ENGINE" image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
    OLD_VERSION="$("$ENGINE" run --rm --entrypoint /usr/sbin/smartdns "$IMAGE_TAG" -v 2>/dev/null || true)"
    log "当前已有镜像版本: ${OLD_VERSION:-未知}"
fi

# ---------- 构建 ----------
log "开始构建镜像 ${IMAGE_TAG} (arch=${SMARTDNS_ARCH})..."
# shellcheck disable=SC2086
"$ENGINE" build ${CACHE_FLAG} ${BUILD_ARGS} -t "$IMAGE_TAG" "$SCRIPT_DIR"

# ---------- 获取新版本并打版本号 tag ----------
NEW_VERSION="$("$ENGINE" run --rm --entrypoint /usr/sbin/smartdns "$IMAGE_TAG" -v 2>/dev/null || true)"
log "构建完成，新版本: ${NEW_VERSION:-未知}"

VERSION_TAG=""
if [ -n "$NEW_VERSION" ]; then
    # 从 "smartdns 1.2026.06.28-1614 (Release48.2)" 中提取形如 Release48.2 的短标签
    SHORT_VER="$(echo "$NEW_VERSION" | sed -n 's/.*(\(.*\))/\1/p')"
    [ -z "$SHORT_VER" ] && SHORT_VER="$(echo "$NEW_VERSION" | awk '{print $2}')"
    REPO="${IMAGE_TAG%%:*}"
    VERSION_TAG="${REPO}:${SHORT_VER}"
    "$ENGINE" tag "$IMAGE_TAG" "$VERSION_TAG"
    log "已额外打标签: ${VERSION_TAG}"
fi

if [ -n "$OLD_VERSION" ] && [ "$OLD_VERSION" = "$NEW_VERSION" ]; then
    log "版本未发生变化 (${NEW_VERSION})，无需重启容器。"
    DO_RESTART=0
fi

# ---------- 重启容器（可选）----------
if [ "$DO_RESTART" = "1" ]; then
    if "$ENGINE" ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
        log "重启容器 ${CONTAINER_NAME} 以应用新镜像..."
        "$ENGINE" rm -f "$CONTAINER_NAME" >/dev/null

        VOL_SUFFIX=""
        [ "$SELINUX_LABEL" = "1" ] && VOL_SUFFIX=":Z"

        "$ENGINE" run -d \
            --name "$CONTAINER_NAME" \
            --restart unless-stopped \
            -p 53:53/udp \
            -p 53:53/tcp \
            -v "$SCRIPT_DIR/etc/smartdns:/etc/smartdns${VOL_SUFFIX}" \
            "$IMAGE_TAG" >/dev/null
        log "容器已重启: ${CONTAINER_NAME}"
    else
        log "未找到名为 ${CONTAINER_NAME} 的容器，跳过重启（可手动用 ${ENGINE} run 启动）。"
    fi
fi

log "全部完成。当前镜像: ${IMAGE_TAG}${VERSION_TAG:+ / ${VERSION_TAG}}"
