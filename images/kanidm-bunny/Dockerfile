FROM alpine:3.22 AS s6-overlay

ARG S6_OVERLAY_VERSION=3.2.1.0
ARG TARGETARCH=amd64

RUN apk add --no-cache \
    ca-certificates \
    curl \
    xz

RUN case "$TARGETARCH" in \
      amd64) s6_arch=x86_64 ;; \
      arm64) s6_arch=aarch64 ;; \
      *) echo "unsupported TARGETARCH=$TARGETARCH" >&2; exit 1 ;; \
    esac && \
    mkdir -p /s6-root && \
    curl -fsSL "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz" -o /tmp/s6-overlay-noarch.tar.xz && \
    curl -fsSL "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${s6_arch}.tar.xz" -o /tmp/s6-overlay-arch.tar.xz && \
    tar -C /s6-root -Jxpf /tmp/s6-overlay-noarch.tar.xz && \
    tar -C /s6-root -Jxpf /tmp/s6-overlay-arch.tar.xz

FROM golang:1.25.4-alpine3.22 AS ops-api

WORKDIR /src
COPY ops-api/go.mod ./
COPY ops-api/main.go ./
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o /out/kanidm-ops-api .

FROM kanidm/server:1.10.3

COPY --from=busybox:1.37.0-musl /bin/busybox /bin/busybox
SHELL ["/bin/busybox", "sh", "-c"]

COPY --from=s6-overlay /s6-root /
COPY --from=ops-api /out/kanidm-ops-api /usr/local/bin/kanidm-ops-api
COPY rootfs/ /

RUN /bin/busybox --install -s /bin && \
    mkdir -p /run /var && \
    rm -rf /var/run && \
    ln -s /run /var/run && \
    chmod +x \
      /usr/local/bin/generate-kanidm-config \
      /usr/local/bin/run-kanidm-config \
      /usr/local/bin/run-kanidm-server \
      /usr/local/bin/run-kanidm-ops-api \
      /usr/local/bin/finish-kanidm-server \
      /usr/local/bin/kanidm-ops-api \
      /etc/s6-overlay/s6-rc.d/kanidm-config/up \
      /etc/s6-overlay/s6-rc.d/kanidm-server/run \
      /etc/s6-overlay/s6-rc.d/kanidm-server/finish \
      /etc/s6-overlay/s6-rc.d/kanidm-ops-api/run

VOLUME ["/data"]
ENTRYPOINT ["/init"]
