FROM alpine:3.20

LABEL maintainer="you@example.com" \
      description="SmartDNS on Alpine Linux (static binary)"

# smartdns 官方发布的是静态编译二进制，无 glibc/musl 依赖，可直接在 Alpine 上运行
# 使用 latest/download 别名，始终指向最新 Release，不需要跟踪具体版本号/文件名
ARG SMARTDNS_ARCH=x86_64
ARG SMARTDNS_BASE_URL=https://github.com/pymumu/smartdns/releases/latest/download
ARG SMARTDNS_CONF_URL=https://raw.githubusercontent.com/pymumu/smartdns/master/etc/smartdns/smartdns.conf

RUN apk add --no-cache ca-certificates tzdata wget \
    && wget -O /usr/sbin/smartdns "${SMARTDNS_BASE_URL}/smartdns-${SMARTDNS_ARCH}" \
    && chmod +x /usr/sbin/smartdns \
    && mkdir -p /etc/smartdns /var/log/smartdns \
    && wget -O /etc/smartdns/smartdns.conf.default "${SMARTDNS_CONF_URL}" \
    && apk del wget \
    && /usr/sbin/smartdns -v

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 53/udp 53/tcp

VOLUME ["/etc/smartdns"]

ENTRYPOINT ["/entrypoint.sh"]
