# Build stage: Get busybox
FROM busybox:1.37.0 AS busybox_builder

# Main image
FROM fluent/fluent-bit:4.2.2 AS base

# Copy busybox from builder stage
COPY --from=busybox_builder /bin/busybox /bin/busybox

# Labels
LABEL description="MOV.AI Log Agent - Fluent Bit based log collector and forwarder" \
      maintainer="devops@mov.ai" \
      org.opencontainers.image.source="https://github.com/MOV-AI/containers-log-agent" \
      org.opencontainers.image.documentation="https://github.com/MOV-AI/containers-log-agent/blob/main/README.md" \
      org.opencontainers.image.vendor="MOV.AI" \
      org.opencontainers.image.title="MOV.AI Log Agent"

# Configuration Files: YAML Format
# - fluent-bit-manager.yaml: Configuration for manager/aggregator role
# - fluent-bit-worker.yaml: Configuration for worker/agent role
# - fluent-bit.yaml: Common Fluent Bit settings (e.g., service, parsers, filters)
# - parsers.conf: Log parsing rules for different log formats
# - extract_container.lua: Lua script for Docker container metadata extraction
COPY files/*.yaml /fluent-bit/etc/
COPY files/*.conf /fluent-bit/etc/
COPY files/*.lua /fluent-bit/etc/

# Environment Variables
ENV LOG_LEVEL=info
ENV DEVICE_NAME=manager
ENV APP_NAME=default
ENV LOKI_HOST=loki
ENV LOKI_PORT=3100

HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 CMD ["/bin/busybox", "pidof", "fluent-bit"]

CMD ["/fluent-bit/bin/fluent-bit", "-c", "/fluent-bit/etc/fluent-bit.yaml"]
