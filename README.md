### 启动容器

你可以通过映射端口的方式启动，或者直接使用 `host` 网络模式（推荐在软路由或网关设备上使用 host 模式以避免 NAT 影响 DNS 解析效率）。

**方案 A: 端口映射模式 (推荐常规环境)**

```
podman run -d \
  --name smartdns \
  --restart on-failure \
  -p 53:53/udp \
  -p 53:53/tcp \
  -p 6080:6080 \
  -v /etc/smartdns:/etc/smartdns \
  -v /var/lib/smartdns:/var/lib/smartdns \
  -v /var/log/smartdns:/var/log/smartdns \
  docker.io/xlousp/smartdns:latest
```

**方案 B: Host 网络模式 (推荐网关/旁路由环境)**

```
podman run -d \
  --name smartdns \
  --network host \
  --restart on-failure \
  -v /etc/smartdns:/etc/smartdns \
  -v /var/lib/smartdns:/var/lib/smartdns \
  -v /var/log/smartdns:/var/log/smartdns \
  docker.io/xlousp/smartdns:latest
```
