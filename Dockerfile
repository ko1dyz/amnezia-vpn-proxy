FROM golang:1.25-bookworm AS build
RUN apt-get update && apt-get install -y --no-install-recommends \
      git make gcc libc6-dev libssl-dev libpcre2-dev \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
# Build the AmneziaWG userspace implementation.
RUN git clone --depth 1 https://github.com/amnezia-vpn/amneziawg-go.git \
 && make -C amneziawg-go
# awg / awg-quick
RUN git clone --depth 1 https://github.com/amnezia-vpn/amneziawg-tools.git \
 && make -C amneziawg-tools/src \
 && make -C amneziawg-tools/src install DESTDIR=/out \
      WITH_WGQUICK=yes WITH_SYSTEMDUNITS=no WITH_BASHCOMPLETION=no
# 3proxy
RUN git clone --depth 1 https://github.com/3proxy/3proxy.git \
 && make -C 3proxy -f Makefile.Linux

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      bash iproute2 iptables procps curl ca-certificates libssl3 libpcre2-8-0 \
 && rm -rf /var/lib/apt/lists/*
COPY --from=build /src/amneziawg-go/amneziawg-go /usr/bin/amneziawg-go
COPY --from=build /out/usr/bin/awg /out/usr/bin/awg-quick /usr/bin/
# Skip the sysctl write when Compose has already set the value; /proc/sys is read-only.
RUN sed -i 's|\[\[ $proto == -4 \]\] && cmd sysctl -q net\.ipv4\.conf\.all\.src_valid_mark=1|[[ $proto == -4 ]] \&\& [[ $(sysctl -n net.ipv4.conf.all.src_valid_mark) != 1 ]] \&\& cmd sysctl -q net.ipv4.conf.all.src_valid_mark=1|' /usr/bin/awg-quick
COPY --from=build /src/3proxy/bin/3proxy /usr/bin/3proxy
COPY 3proxy.cfg /etc/3proxy/3proxy.cfg
COPY --chmod=755 entrypoint.sh /entrypoint.sh
EXPOSE 3128
ENTRYPOINT ["/entrypoint.sh"]
