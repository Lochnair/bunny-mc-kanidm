FROM kanidm/server:1.10.3

COPY --from=busybox:1.37.0-musl /bin/busybox /bin/busybox
SHELL ["/bin/busybox", "sh", "-c"]

COPY entrypoint.sh /usr/local/bin/kanidm-bunny-entrypoint
RUN /bin/busybox --install -s /bin && chmod +x /usr/local/bin/kanidm-bunny-entrypoint

VOLUME ["/data"]
ENTRYPOINT ["/usr/local/bin/kanidm-bunny-entrypoint"]
