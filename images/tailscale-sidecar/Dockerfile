FROM tailscale/tailscale:v1.98.3

COPY entrypoint.sh /usr/local/bin/tailscale-sidecar-entrypoint
RUN chmod +x /usr/local/bin/tailscale-sidecar-entrypoint

VOLUME ["/var/lib/tailscale"]
ENTRYPOINT ["/usr/local/bin/tailscale-sidecar-entrypoint"]
