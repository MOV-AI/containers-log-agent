#!/bin/busybox sh
#=============================================================================
# Fluent Bit Entrypoint - Selects config based on feature flags
# Feature Flags (optimized defaults for low CPU usage):
#   ENABLE_ADVANCED_PARSING (false) - service routing + lua + structured parsing
#   ENABLE_COMPRESSION (true) - snappy compression
#   ENABLE_STORAGE_METRICS (false) - storage statistics
#   ENABLE_HTTP_METRICS (false) - HTTP metrics server
#=============================================================================

set -e

# Feature flag defaults
ENABLE_ADVANCED_PARSING="${ENABLE_ADVANCED_PARSING:=false}"
ENABLE_COMPRESSION="${ENABLE_COMPRESSION:=true}"
ENABLE_STORAGE_METRICS="${ENABLE_STORAGE_METRICS:=false}"
ENABLE_HTTP_METRICS="${ENABLE_HTTP_METRICS:=false}"

# Select configuration file based on ENABLE_ADVANCED_PARSING
if [ "$ENABLE_ADVANCED_PARSING" = "true" ]; then
    CONFIG_FILE="/fluent-bit/etc/fluent-bit-advanced-parsing.yaml"
    echo "✓ Advanced parsing enabled (service routing + lua + structured parsers)"
else
    CONFIG_FILE="/fluent-bit/etc/fluent-bit.yaml"
    echo "✗ Advanced parsing disabled (generic parsing only)"
fi

# Log feature flag configuration
echo "=== Fluent Bit Feature Flags ==="
echo "Config: $CONFIG_FILE"
echo "ENABLE_ADVANCED_PARSING: $ENABLE_ADVANCED_PARSING"
echo "ENABLE_COMPRESSION: $ENABLE_COMPRESSION"
echo "ENABLE_STORAGE_METRICS: $ENABLE_STORAGE_METRICS"
echo "ENABLE_HTTP_METRICS: $ENABLE_HTTP_METRICS"
echo ""

# Convert boolean flags to actual fluent-bit values and export them
if [ "$ENABLE_COMPRESSION" = "true" ]; then
    ENABLE_COMPRESSION="snappy"
    echo "✓ Snappy compression enabled"
else
    ENABLE_COMPRESSION="off"
    echo "✗ Snappy compression disabled"
fi

if [ "$ENABLE_STORAGE_METRICS" = "true" ]; then
    ENABLE_STORAGE_METRICS="on"
    echo "✓ Storage metrics enabled"
else
    ENABLE_STORAGE_METRICS="off"
    echo "✗ Storage metrics disabled"
fi

if [ "$ENABLE_HTTP_METRICS" = "true" ]; then
    ENABLE_HTTP_METRICS="true"
    echo "✓ HTTP metrics server enabled"
else
    ENABLE_HTTP_METRICS="false"
    echo "✗ HTTP metrics server disabled"
fi

# Export all variables for fluent-bit to use
export ENABLE_COMPRESSION
export ENABLE_STORAGE_METRICS
export ENABLE_HTTP_METRICS
export ENABLE_ADVANCED_PARSING

echo ""
echo "Starting Fluent Bit with config: $CONFIG_FILE"
exec /fluent-bit/bin/fluent-bit -c "$CONFIG_FILE"
