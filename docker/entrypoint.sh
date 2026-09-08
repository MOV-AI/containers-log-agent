#!/bin/busybox sh
#=============================================================================
# Fluent Bit Entrypoint - Selects config based on feature flags
# Feature Flags (optimized defaults for low CPU usage):
#   ENABLE_ADVANCED_PARSING (false) - service routing + lua + structured parsing
#   SECURITY_LOGS_ENABLE (false) - host security logs ingestion (journald/audit/auth)
#   SECURITY_LOGS_STRICT (false) - fail startup if required security sources are unavailable
#   TELEMETRY_ENABLE (false) - MOV.AI platform telemetry socket -> Mimir (OTLP) + Loki
#   ENABLE_LOKI_OUTPUT (true) - disable when no Loki server is deployed, to skip Loki outputs/filters
#   ENABLE_MIMIR_OUTPUT (true) - disable when no Mimir server is deployed, to skip the telemetry OTLP output
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
TELEMETRY_ENABLE="${TELEMETRY_ENABLE:=false}"
ENABLE_LOKI_OUTPUT="${ENABLE_LOKI_OUTPUT:=true}"
ENABLE_MIMIR_OUTPUT="${ENABLE_MIMIR_OUTPUT:=true}"
ENABLE_COMPRESSION="${ENABLE_COMPRESSION:=true}"
ENABLE_STORAGE_METRICS="${ENABLE_STORAGE_METRICS:=false}"
ENABLE_HTTP_METRICS="${ENABLE_HTTP_METRICS:=false}"
ENABLE_TELEMETRY_COMPRESSION="${ENABLE_TELEMETRY_COMPRESSION:=false}"

# Fluent Bit config defaults (used by ${VAR} interpolation in yaml files)
FLUSH_INTERVAL="${FLUSH_INTERVAL:=5}"
FLUENT_BIT_BACKLOG_MEM_LIMIT="${FLUENT_BIT_BACKLOG_MEM_LIMIT:=10M}"
FLUENT_BIT_LOKI_TOTAL_LIMIT_SIZE="${FLUENT_BIT_LOKI_TOTAL_LIMIT_SIZE:=500M}"
FLUENT_BIT_BUFFER_MAX_SIZE="${FLUENT_BIT_BUFFER_MAX_SIZE:=6M}"
FLUENT_BIT_HOSTNAME="${FLUENT_BIT_HOSTNAME:=${DEVICE_NAME:-unknown}}"
MIMIR_HOST="${MIMIR_HOST:=metrics-store}"
MIMIR_PORT="${MIMIR_PORT:=8080}"
MOVAI_TELEMETRY_SOCKET="${MOVAI_TELEMETRY_SOCKET:=/opt/mov.ai/comm/movai-platform-metrics.sock}"
LOG_LEVEL="${LOG_LEVEL:=warning}"

# Startup logs mimic the fluent-bit line format so the whole stream stays homogeneous.
case "$LOG_LEVEL" in
    error) LOG_VERBOSITY=1 ;;
    warn|warning) LOG_VERBOSITY=2 ;;
    debug|trace) LOG_VERBOSITY=4 ;;
    *) LOG_VERBOSITY=3 ;;
esac

_log() {
    level="$1"
    shift
    printf '[%s] [%5s] [entrypoint] %s\n' "$("$BUSYBOX_BIN" date '+%Y/%m/%d %H:%M:%S')" "$level" "$*"
}

log_error() { _log error "$@" >&2; }
log_warn() { if [ "$LOG_VERBOSITY" -ge 2 ]; then _log warn "$@" >&2; fi; }
# Startup summary is always emitted, regardless of LOG_LEVEL.
log_info() { _log info "$@"; }
log_detail() { if [ "$LOG_VERBOSITY" -ge 3 ]; then _log info "$@"; fi; }

SECURITY_INPUTS_FRAGMENT="/fluent-bit/etc/fluent-bit-security-inputs.yamlfrag"
SECURITY_FILTERS_FRAGMENT="/fluent-bit/etc/fluent-bit-security-filters.yamlfrag"
SECURITY_OUTPUTS_FRAGMENT="/fluent-bit/etc/fluent-bit-security-outputs.yamlfrag"

TELEMETRY_INPUTS_FRAGMENT="/fluent-bit/etc/fluent-bit-telemetry-inputs.yamlfrag"
TELEMETRY_FILTERS_FRAGMENT="/fluent-bit/etc/fluent-bit-telemetry-filters.yamlfrag"
TELEMETRY_FILTERS_MIMIR_FRAGMENT="/fluent-bit/etc/fluent-bit-telemetry-filters-mimir.yamlfrag"
TELEMETRY_OUTPUTS_LOKI_FRAGMENT="/fluent-bit/etc/fluent-bit-telemetry-outputs-loki.yamlfrag"
TELEMETRY_OUTPUTS_MIMIR_FRAGMENT="/fluent-bit/etc/fluent-bit-telemetry-outputs-mimir.yamlfrag"

# Core Loki filters/outputs have a generic and an advanced-parsing variant, selected below.
if [ "$ENABLE_ADVANCED_PARSING" = "true" ]; then
    CORE_LOKI_FILTERS_FRAGMENT="/fluent-bit/etc/fluent-bit-core-loki-filters-advanced.yamlfrag"
    CORE_LOKI_OUTPUTS_FRAGMENT="/fluent-bit/etc/fluent-bit-core-loki-outputs-advanced.yamlfrag"
else
    CORE_LOKI_FILTERS_FRAGMENT="/fluent-bit/etc/fluent-bit-core-loki-filters.yamlfrag"
    CORE_LOKI_OUTPUTS_FRAGMENT="/fluent-bit/etc/fluent-bit-core-loki-outputs.yamlfrag"
fi

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

# Echoes a comma-separated list of the unreadable fragments among its arguments.
unreadable_fragments() {
    missing=""
    for fragment in "$@"; do
        if [ ! -r "$fragment" ]; then
            if [ -z "$missing" ]; then
                missing="$fragment"
            else
                missing="$missing, $fragment"
            fi
        fi
    done
    echo "$missing"
}

apply_fragment() {
    inject_fragment "$WORK_CONFIG" "${WORK_CONFIG}.next" "$1" "$2"
    "$BUSYBOX_BIN" mv -f "${WORK_CONFIG}.next" "$WORK_CONFIG"
}

compose_runtime_config() {
    base="$1"
    runtime="$2"

    # Security logs are only ever shipped to Loki, so skip the whole pipeline when Loki is disabled.
    inject_security="$SECURITY_LOGS_ENABLE"
    if [ "$inject_security" = "true" ] && [ "$ENABLE_LOKI_OUTPUT" != "true" ]; then
        log_warn "SECURITY_LOGS_ENABLE=true but ENABLE_LOKI_OUTPUT=false; skipping security log ingestion"
        inject_security="false"
    fi
    if [ "$inject_security" = "true" ]; then
        missing="$(unreadable_fragments "$SECURITY_INPUTS_FRAGMENT" "$SECURITY_FILTERS_FRAGMENT" "$SECURITY_OUTPUTS_FRAGMENT")"
        if [ -n "$missing" ]; then
            if [ "$SECURITY_LOGS_STRICT" = "true" ]; then
                log_error "missing security fragments: $missing"
                exit 1
            fi

            log_warn "missing security fragments: $missing; continuing without security fragment injection"
            inject_security="false"
        fi
    fi

    # Telemetry is only worth ingesting if at least one of its backends (Loki, Mimir) is enabled.
    inject_telemetry="$TELEMETRY_ENABLE"
    if [ "$inject_telemetry" = "true" ] && [ "$ENABLE_LOKI_OUTPUT" != "true" ] && [ "$ENABLE_MIMIR_OUTPUT" != "true" ]; then
        log_warn "TELEMETRY_ENABLE=true but both ENABLE_LOKI_OUTPUT and ENABLE_MIMIR_OUTPUT are false; skipping telemetry ingestion"
        inject_telemetry="false"
    fi
    inject_telemetry_loki="false"
    inject_telemetry_mimir="false"
    if [ "$inject_telemetry" = "true" ]; then
        telemetry_fragments="$TELEMETRY_INPUTS_FRAGMENT $TELEMETRY_FILTERS_FRAGMENT"
        if [ "$ENABLE_LOKI_OUTPUT" = "true" ]; then
            telemetry_fragments="$telemetry_fragments $TELEMETRY_OUTPUTS_LOKI_FRAGMENT"
        fi
        if [ "$ENABLE_MIMIR_OUTPUT" = "true" ]; then
            telemetry_fragments="$telemetry_fragments $TELEMETRY_FILTERS_MIMIR_FRAGMENT $TELEMETRY_OUTPUTS_MIMIR_FRAGMENT"
        fi
        missing="$(unreadable_fragments $telemetry_fragments)"
        if [ -n "$missing" ]; then
            log_error "missing telemetry fragments: $missing"
            exit 1
        fi

        socket_dir="$("$BUSYBOX_BIN" dirname "$MOVAI_TELEMETRY_SOCKET")"
        if [ ! -d "$socket_dir" ]; then
            log_error "TELEMETRY_ENABLE=true but $socket_dir is not mounted"
            exit 1
        fi

        inject_telemetry_loki="$ENABLE_LOKI_OUTPUT"
        inject_telemetry_mimir="$ENABLE_MIMIR_OUTPUT"
    fi

    WORK_CONFIG="${runtime}.work"
    "$BUSYBOX_BIN" cp -f "$base" "$WORK_CONFIG"

    if [ "$ENABLE_LOKI_OUTPUT" = "true" ]; then
        apply_fragment "#__CORE_LOKI_FILTERS__" "$CORE_LOKI_FILTERS_FRAGMENT"
        apply_fragment "#__CORE_LOKI_OUTPUTS__" "$CORE_LOKI_OUTPUTS_FRAGMENT"
    fi

    if [ "$inject_security" = "true" ]; then
        apply_fragment "#__SECURITY_INPUTS__" "$SECURITY_INPUTS_FRAGMENT"
        apply_fragment "#__SECURITY_FILTERS__" "$SECURITY_FILTERS_FRAGMENT"
        apply_fragment "#__SECURITY_OUTPUTS__" "$SECURITY_OUTPUTS_FRAGMENT"
    fi

    if [ "$inject_telemetry" = "true" ]; then
        apply_fragment "#__TELEMETRY_INPUTS__" "$TELEMETRY_INPUTS_FRAGMENT"
        apply_fragment "#__TELEMETRY_FILTERS__" "$TELEMETRY_FILTERS_FRAGMENT"
    fi
    if [ "$inject_telemetry_mimir" = "true" ]; then
        apply_fragment "#__TELEMETRY_FILTERS_MIMIR__" "$TELEMETRY_FILTERS_MIMIR_FRAGMENT"
        apply_fragment "#__TELEMETRY_OUTPUTS_MIMIR__" "$TELEMETRY_OUTPUTS_MIMIR_FRAGMENT"
    fi
    if [ "$inject_telemetry_loki" = "true" ]; then
        apply_fragment "#__TELEMETRY_OUTPUTS_LOKI__" "$TELEMETRY_OUTPUTS_LOKI_FRAGMENT"
    fi

    "$BUSYBOX_BIN" grep -vE '#__(SECURITY|TELEMETRY|CORE_LOKI)_.*__' "$WORK_CONFIG" > "$runtime"
    "$BUSYBOX_BIN" rm -f "$WORK_CONFIG"
}

log_info "MOV.AI Log Agent starting (hostname=$FLUENT_BIT_HOSTNAME, app=${APP_NAME:-default})"

# Select configuration file based on feature flags
if [ "$ENABLE_ADVANCED_PARSING" = "true" ]; then
    BASE_CONFIG_FILE="/fluent-bit/etc/fluent-bit-advanced-parsing.yaml"
    PARSING_MODE="advanced (service routing + lua + structured parsers)"
else
    BASE_CONFIG_FILE="/fluent-bit/etc/fluent-bit.yaml"
    PARSING_MODE="generic"
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
        log_detail "security source available: journald (/hostfs/var/log/journal)"
    else
        log_warn "security source unavailable: /hostfs/var/log/journal"
    fi

    if [ "$has_audit_log" = "true" ]; then
        log_detail "security source available: audit.log"
    else
        log_warn "security source unavailable: /hostfs/var/log/audit/audit.log"
    fi

    if [ "$has_auth_log" = "true" ]; then
        log_detail "security source available: auth fallback logs"
    else
        log_warn "security source unavailable: auth fallback logs (/hostfs/var/log/auth.log, /hostfs/var/log/secure)"
    fi

    if [ "$SECURITY_LOGS_STRICT" = "true" ] \
        && [ "$has_persistent_journal" = "false" ] \
        && [ "$has_runtime_journal" = "false" ] \
        && [ "$has_audit_log" = "false" ] \
        && [ "$has_auth_log" = "false" ]; then
        log_error "SECURITY_LOGS_STRICT=true but no host security log source is available"
        exit 1
    fi
fi

# Convert boolean flags to actual fluent-bit values and export them
if [ "$ENABLE_COMPRESSION" = "true" ]; then
    ENABLE_COMPRESSION="snappy"
else
    ENABLE_COMPRESSION="off"
fi

if [ "$ENABLE_TELEMETRY_COMPRESSION" = "true" ]; then
    ENABLE_TELEMETRY_COMPRESSION="gzip"
else
    ENABLE_TELEMETRY_COMPRESSION="none"
fi

if [ "$ENABLE_STORAGE_METRICS" = "true" ]; then
    ENABLE_STORAGE_METRICS="on"
else
    ENABLE_STORAGE_METRICS="off"
fi

if [ "$ENABLE_HTTP_METRICS" != "true" ]; then
    ENABLE_HTTP_METRICS="false"
fi

# Effective configuration summary
if [ "$ENABLE_LOKI_OUTPUT" != "true" ]; then
    LOKI_TARGET="disabled (ENABLE_LOKI_OUTPUT=false)"
elif [ -z "$LOKI_HOST" ]; then
    LOKI_TARGET="disabled (LOKI_HOST not set)"
    log_warn "LOKI_HOST not set: logs are buffered locally but not sent to any log-aggregator"
else
    LOKI_TARGET="${LOKI_HOST}:${LOKI_PORT:-3100}"
fi

if [ "$ENABLE_MIMIR_OUTPUT" != "true" ]; then
    MIMIR_TARGET="disabled"
elif [ "$inject_telemetry" != "true" ]; then
    MIMIR_TARGET="unused (telemetry disabled)"
else
    MIMIR_TARGET="${MIMIR_HOST}:${MIMIR_PORT}"
fi

log_info "config: $CONFIG_FILE"
log_info "parsing: $PARSING_MODE"
log_info "sources: containers=enabled, security=$inject_security (strict=$SECURITY_LOGS_STRICT), telemetry=$inject_telemetry"
log_info "outputs: loki=$LOKI_TARGET, mimir=$MIMIR_TARGET"
log_info "tuning: compression=$ENABLE_COMPRESSION, telemetry_compression=$ENABLE_TELEMETRY_COMPRESSION, storage_metrics=$ENABLE_STORAGE_METRICS, http_metrics=$ENABLE_HTTP_METRICS, flush=${FLUSH_INTERVAL}s"

if [ "$inject_telemetry" = "true" ]; then
    log_detail "telemetry socket: $MOVAI_TELEMETRY_SOCKET"
fi

# Export all variables for fluent-bit to use
export ENABLE_COMPRESSION
export ENABLE_STORAGE_METRICS
export ENABLE_HTTP_METRICS
export ENABLE_ADVANCED_PARSING
export SECURITY_LOGS_ENABLE
export SECURITY_LOGS_STRICT
export TELEMETRY_ENABLE
export ENABLE_LOKI_OUTPUT
export ENABLE_MIMIR_OUTPUT
export ENABLE_TELEMETRY_COMPRESSION
export MIMIR_HOST
export MIMIR_PORT
export MOVAI_TELEMETRY_SOCKET
export FLUSH_INTERVAL
export FLUENT_BIT_BACKLOG_MEM_LIMIT
export FLUENT_BIT_LOKI_TOTAL_LIMIT_SIZE
export FLUENT_BIT_BUFFER_MAX_SIZE
export FLUENT_BIT_HOSTNAME

log_info "starting fluent-bit (config=$CONFIG_FILE)"
exec /fluent-bit/bin/fluent-bit -c "$CONFIG_FILE" "$@"
