#!/bin/busybox sh
#=============================================================================
# Fluent Bit Entrypoint - Selects config based on feature flags
# Feature Flags (optimized defaults for low CPU usage):
#   ENABLE_ADVANCED_PARSING (false) - service routing + lua + structured parsing
#   SECURITY_LOGS_ENABLE (false) - host security logs ingestion (journald/audit/auth)
#   SECURITY_LOGS_STRICT (false) - fail startup if required security sources are unavailable
#   ENABLE_COMPRESSION (true) - snappy compression
#   ENABLE_STORAGE_METRICS (false) - storage statistics
#   ENABLE_HTTP_METRICS (false) - HTTP metrics server
#=============================================================================

set -e

BUSYBOX_BIN="/bin/busybox"

# Feature flag defaults
ENABLE_ADVANCED_PARSING="${ENABLE_ADVANCED_PARSING:=false}"
SECURITY_LOGS_ENABLE="${SECURITY_LOGS_ENABLE:=false}"
SECURITY_LOGS_STRICT="${SECURITY_LOGS_STRICT:=false}"
ENABLE_COMPRESSION="${ENABLE_COMPRESSION:=true}"
ENABLE_STORAGE_METRICS="${ENABLE_STORAGE_METRICS:=false}"
ENABLE_HTTP_METRICS="${ENABLE_HTTP_METRICS:=false}"

# Fluent Bit config defaults (used by ${VAR} interpolation in yaml files)
FLUSH_INTERVAL="${FLUSH_INTERVAL:=5}"
FLUENT_BIT_BACKLOG_MEM_LIMIT="${FLUENT_BIT_BACKLOG_MEM_LIMIT:=10M}"
FLUENT_BIT_LOKI_TOTAL_LIMIT_SIZE="${FLUENT_BIT_LOKI_TOTAL_LIMIT_SIZE:=500M}"
FLUENT_BIT_BUFFER_MAX_SIZE="${FLUENT_BIT_BUFFER_MAX_SIZE:=6M}"
FLUENT_BIT_HOSTNAME="${FLUENT_BIT_HOSTNAME:=${DEVICE_NAME:-unknown}}"

SECURITY_INPUTS_FRAGMENT="/fluent-bit/etc/fluent-bit-security-inputs.yamlfrag"
SECURITY_FILTERS_FRAGMENT="/fluent-bit/etc/fluent-bit-security-filters.yamlfrag"
SECURITY_OUTPUTS_FRAGMENT="/fluent-bit/etc/fluent-bit-security-outputs.yamlfrag"

inject_fragment() {
    in_file="$1"
    out_file="$2"
    marker="$3"
    fragment="$4"

    "$BUSYBOX_BIN" awk -v m="$marker" -v f="$fragment" '
        $0 ~ m {
            while ((getline line < f) > 0) {
                print line
            }
            close(f)
            next
        }
        { print }
    ' "$in_file" > "$out_file"
}

compose_runtime_config() {
    base="$1"
    runtime="$2"
    missing=""

    if [ "$SECURITY_LOGS_ENABLE" = "true" ]; then
        for fragment in "$SECURITY_INPUTS_FRAGMENT" "$SECURITY_FILTERS_FRAGMENT" "$SECURITY_OUTPUTS_FRAGMENT"; do
            if [ ! -r "$fragment" ]; then
                if [ -z "$missing" ]; then
                    missing="$fragment"
                else
                    missing="$missing, $fragment"
                fi
            fi
        done

        if [ -n "$missing" ]; then
            if [ "$SECURITY_LOGS_STRICT" = "true" ]; then
                echo "ERROR: missing security fragments: $missing"
                exit 1
            fi

            echo "WARN: missing security fragments: $missing"
            echo "WARN: continuing without security fragment injection"
            "$BUSYBOX_BIN" grep -v '#__SECURITY_.*__' "$base" > "$runtime"
            return 0
        fi

        tmp1="${runtime}.tmp1"
        tmp2="${runtime}.tmp2"

        inject_fragment "$base" "$tmp1" "#__SECURITY_INPUTS__" "$SECURITY_INPUTS_FRAGMENT"
        inject_fragment "$tmp1" "$tmp2" "#__SECURITY_FILTERS__" "$SECURITY_FILTERS_FRAGMENT"
        inject_fragment "$tmp2" "$runtime" "#__SECURITY_OUTPUTS__" "$SECURITY_OUTPUTS_FRAGMENT"

        "$BUSYBOX_BIN" rm -f "$tmp1" "$tmp2"
    else
        # Strip markers when security ingestion is disabled.
        "$BUSYBOX_BIN" grep -v '#__SECURITY_.*__' "$base" > "$runtime"
    fi
}

# Select configuration file based on feature flags
if [ "$ENABLE_ADVANCED_PARSING" = "true" ]; then
    BASE_CONFIG_FILE="/fluent-bit/etc/fluent-bit-advanced-parsing.yaml"
    echo "✓ Advanced parsing enabled (service routing + lua + structured parsers)"
    if [ "$SECURITY_LOGS_ENABLE" = "true" ]; then
        echo "✓ Host security ingestion enabled"
    fi
else
    BASE_CONFIG_FILE="/fluent-bit/etc/fluent-bit.yaml"
    echo "✗ Advanced parsing disabled (generic parsing only)"
    if [ "$SECURITY_LOGS_ENABLE" = "true" ]; then
        echo "✓ Host security ingestion enabled"
    fi
fi

CONFIG_FILE="/tmp/fluent-bit-runtime.yaml"
compose_runtime_config "$BASE_CONFIG_FILE" "$CONFIG_FILE"

# Validate host security sources when security ingestion is enabled.
if [ "$SECURITY_LOGS_ENABLE" = "true" ]; then
    has_persistent_journal="false"
    has_runtime_journal="false"
    has_audit_log="false"
    has_auth_log="false"

    [ -d "/hostfs/var/log/journal" ] && has_persistent_journal="true"
    # NOTE: Fluent Bit systemd inputs currently read from /hostfs/var/log/journal only.

    if [ "$has_persistent_journal" = "true" ]; then
        echo "✓ Security source available: journald (/hostfs/var/log/journal)"
    else
        echo "⚠ Security source unavailable: /hostfs/var/log/journal"
    fi

    if [ "$has_audit_log" = "true" ]; then
        echo "✓ Security source available: audit.log"
    else
        echo "⚠ Security source unavailable: /hostfs/var/log/audit/audit.log"
    fi

    if [ "$has_auth_log" = "true" ]; then
        echo "✓ Security source available: auth fallback logs"
    else
        echo "⚠ Security source unavailable: auth fallback logs (/hostfs/var/log/auth.log, /hostfs/var/log/secure)"
    fi

    if [ "$SECURITY_LOGS_STRICT" = "true" ] \
        && [ "$has_persistent_journal" = "false" ] \
        && [ "$has_runtime_journal" = "false" ] \
        && [ "$has_audit_log" = "false" ] \
        && [ "$has_auth_log" = "false" ]; then
        echo "ERROR: SECURITY_LOGS_STRICT=true but no host security log source is available"
        exit 1
    fi
fi

# Log feature flag configuration
echo "=== Fluent Bit Feature Flags ==="
echo "Config: $CONFIG_FILE"
echo "ENABLE_ADVANCED_PARSING: $ENABLE_ADVANCED_PARSING"
echo "SECURITY_LOGS_ENABLE: $SECURITY_LOGS_ENABLE"
echo "SECURITY_LOGS_STRICT: $SECURITY_LOGS_STRICT"
echo "ENABLE_COMPRESSION: $ENABLE_COMPRESSION"
echo "ENABLE_STORAGE_METRICS: $ENABLE_STORAGE_METRICS"
echo "ENABLE_HTTP_METRICS: $ENABLE_HTTP_METRICS"

# Check Loki availability
if [ -z "$LOKI_HOST" ]; then
    echo "Loki disabled: LOKI_HOST not set (logs will be buffered locally but not sent to any log-aggregator)"
else
    echo "Loki enabled: LOKI_HOST=$LOKI_HOST"
fi
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
export SECURITY_LOGS_ENABLE
export SECURITY_LOGS_STRICT
export FLUSH_INTERVAL
export FLUENT_BIT_BACKLOG_MEM_LIMIT
export FLUENT_BIT_LOKI_TOTAL_LIMIT_SIZE
export FLUENT_BIT_BUFFER_MAX_SIZE
export FLUENT_BIT_HOSTNAME

echo ""
echo "Starting Fluent Bit with config: $CONFIG_FILE"
exec /fluent-bit/bin/fluent-bit -c "$CONFIG_FILE" "$@"
