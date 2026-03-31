# Build stage: Get busybox
FROM busybox:1.37.0 AS busybox_builder

# Main image
FROM fluent/fluent-bit:4.2.3 AS base

# Copy busybox from builder stage
COPY --from=busybox_builder /bin/busybox /bin/busybox

# Labels
LABEL description="MOV.AI Log Agent - Fluent Bit based log collector and forwarder" \
      maintainer="devops@mov.ai" \
      org.opencontainers.image.source="https://github.com/MOV-AI/containers-log-agent" \
      org.opencontainers.image.documentation="https://github.com/MOV-AI/containers-log-agent/blob/main/README.md" \
      org.opencontainers.image.vendor="MOV.AI" \
      org.opencontainers.image.title="MOV.AI Log Agent"

# Configuration Files
# - fluent-bit.yaml: Generic parsing configuration
# - fluent-bit-advanced-parsing.yaml: Full-featured with service routing and Lua
# - parsers.conf: Log parsing rules for different log formats
# - parse_callback_tags.lua: Lua script for tag extraction and ANSI stripping
COPY files/fluent-bit.yaml /fluent-bit/etc/
COPY files/fluent-bit-*.yaml /fluent-bit/etc/
COPY files/*.conf /fluent-bit/etc/
COPY files/*.lua /fluent-bit/etc/

# Entrypoint script for feature flag selection
COPY docker/entrypoint.sh /

# Environment Variables
ENV LOG_LEVEL=info
ENV DEVICE_NAME=manager
ENV APP_NAME=default
ENV LOKI_HOST=loki
ENV LOKI_PORT=3100

# Feature Flags
ENV ENABLE_ADVANCED_PARSING=false
ENV ENABLE_COMPRESSION=true
ENV ENABLE_STORAGE_METRICS=false
ENV ENABLE_HTTP_METRICS=false

HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 CMD ["/bin/busybox", "pidof", "fluent-bit"]

ENTRYPOINT ["/entrypoint.sh"]
