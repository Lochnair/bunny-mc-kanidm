FROM alpine:3.22

RUN apk add --no-cache \
    ca-certificates \
    netcat-openbsd \
    socat

COPY entrypoint.sh /usr/local/bin/socat-forwarder-entrypoint
RUN chmod +x /usr/local/bin/socat-forwarder-entrypoint

ENTRYPOINT ["/usr/local/bin/socat-forwarder-entrypoint"]
