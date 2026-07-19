#!/bin/sh
set -e

CONF_DIR="/etc/smartdns"
CONF_FILE="${CONF_DIR}/smartdns.conf"

# 如果用户挂载的是空目录（第一次运行），用默认配置初始化，方便后续直接编辑
if [ ! -f "$CONF_FILE" ]; then
    echo "[entrypoint] ${CONF_FILE} 不存在，使用默认配置初始化..."
    cp /etc/smartdns/smartdns.conf.default "$CONF_FILE"
fi

# -f 前台运行（容器内必须前台，否则容器会立即退出）
# -x 输出详细日志到标准输出，方便 docker logs 查看
exec /usr/sbin/smartdns -f -x -c "$CONF_FILE"
