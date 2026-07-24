FROM ubuntu:latest AS smartdns-builder
LABEL previous-stage=smartdns-builder
# prepare builder
ARG OPENSSL_VER=3.5.4
ARG NODE_VERSION=20.x
RUN apt update && \
    apt install -y binutils perl curl make gcc clang wget unzip ca-certificates && \
    update-ca-certificates && \
    curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION} | bash - && \
    apt install -y nodejs && \
    node --version && npm --version && \
    \
    curl https://sh.rustup.rs -sSf | sh -s -- -y && \
    export PATH="$HOME/.cargo/bin:$PATH" && \
    \
    mkdir -p /build/openssl && \
    cd /build/openssl && \
    curl -sSL https://www.github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VER}/openssl-${OPENSSL_VER}.tar.gz | tar --strip-components=1 -zxv && \
    \
    OPENSSL_OPTIONS="no-argon2 no-aria no-async no-bf no-blake2 no-camellia no-cmp no-cms " \
    OPENSSL_OPTIONS="$OPENSSL_OPTIONS no-comp no-des no-dh no-dsa no-ec2m no-engine no-gost "\
    OPENSSL_OPTIONS="$OPENSSL_OPTIONS no-http no-idea no-legacy no-md4 no-mdc2 no-multiblock "\
    OPENSSL_OPTIONS="$OPENSSL_OPTIONS no-nextprotoneg no-ocb no-ocsp no-rc2 no-rc4 no-rmd160 "\
    OPENSSL_OPTIONS="$OPENSSL_OPTIONS no-scrypt no-seed no-siphash no-siv no-sm2 no-sm3 no-sm4 "\
    OPENSSL_OPTIONS="$OPENSSL_OPTIONS no-srp no-srtp no-ts no-whirlpool no-apps no-ssl-trace "\
    OPENSSL_OPTIONS="$OPENSSL_OPTIONS no-ssl no-ssl3 no-tests -Os" \
    cd /build/openssl && \
    if [ "$(uname -m)" = "aarch64" ]; then \
        ./config --prefix=/opt/build $OPENSSL_OPTIONS -mno-outline-atomics ; \
    else \
        ./config --prefix=/opt/build $OPENSSL_OPTIONS ; \
    fi && \
    mkdir -p /opt/build/lib /opt/build/lib64 && \
    make all -j8 && make install_sw && \
    cd / && rm -rf /build
# do make
COPY . /build/smartdns/
RUN cd /build/smartdns && \
    export CFLAGS="-I /opt/build/include" && \
    export LDFLAGS="-L /opt/build/lib -L /opt/build/lib64" && \
    export PATH="$HOME/.cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" && \
    rm -fr /build/smartdns/package/*.tar.gz && \
    sh ./package/build-pkg.sh --platform linux --arch `dpkg --print-architecture` --with-ui --static && \
    \
    ( cd package && tar -xvf *.tar.gz && chmod a+x smartdns/etc/init.d/smartdns ) && \
    \
    mkdir -p /release/var/log /release/run /release/var/lib/smartdns && \
    cp package/smartdns/etc /release/ -a && \
    cp package/smartdns/usr /release/ -a && \
    rm -f /release/usr/local/smartdns/lib/libssl* && \
    rm -f /release/usr/local/smartdns/lib/libcrypto* && \
    cp /opt/build/lib/lib*.so* /release/usr/local/lib/smartdns/lib/ -a 2>/dev/null || true && \
    cp /opt/build/lib64/lib*.so* /release/usr/local/lib/smartdns/lib/ -a 2>/dev/null || true && \
    cd / && rm -rf /build

FROM busybox:stable-musl
ARG SMARTDNS_VERSION=unknown
LABEL org.opencontainers.image.title="smartdns" \
      org.opencontainers.image.version="${SMARTDNS_VERSION}" \
      org.opencontainers.image.source="https://github.com/pymumu/smartdns"
COPY --from=smartdns-builder /release/ /
# 使用本仓库预设的 smartdns 配置文件覆盖默认配置，
# 保证容器在未挂载 /etc/smartdns 时也能开箱即用。
# 构建上下文（build context）需要在根目录下包含本仓库的 smartdns/ 目录。
COPY smartdns/smartdns.conf /etc/smartdns/smartdns.conf
COPY smartdns/hosts.conf /etc/smartdns/hosts.conf
COPY smartdns/direct-domain-list.conf /etc/smartdns/direct-domain-list.conf
COPY smartdns/proxy-domain-list.conf /etc/smartdns/proxy-domain-list.conf
EXPOSE 53/udp 6080/tcp
VOLUME ["/etc/smartdns/", "/var/lib/smartdns/"]
CMD ["/usr/sbin/smartdns", "-f", "-x"]
