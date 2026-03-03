# MOV.AI Log Agent

A containerized log agent based on [Fluent Bit](https://docs.fluentbit.io/) that collects and forwards logs from MOV.AI services and Docker containers to a centralized log aggregation system (Loki).

## Overview

The Log Agent is a lightweight, efficient logging solution designed for the MOV.AI platform. It runs as a sidecar or standalone service to collect logs from various sources and forward them to a centralized Loki instance for aggregation, analysis, and visualization.

### Key Features

- **Lightweight**: Built on Fluent Bit for minimal resource footprint
- **Multi-role Support**: Templated configurations for manager and worker nodes
- **Loki Integration**: Direct integration with Grafana Loki for log storage
- **Buffered Output**: Configurable storage and buffering for reliability
- **HTTP Metrics**: Built-in HTTP server for monitoring and metrics
- **Container-aware**: Can extract container metadata from logs
- **Compression**: Snappy compression support for efficient transmission

## Configuration

The Log Agent uses environment variable-driven Fluent Bit configuration files:

- **Input**:
  - Forward protocol listener on port 24224 for logs
  - Forward protocol listener on port 24225 for metrics / notifications / etc ...
- **Storage**: Local buffer storage at `/var/log/flb-storage/` with 10MB memory limit
- **Workers**: 2 worker threads for concurrent processing
- **Compression**: Snappy compression enabled
- **Parsing**: Conditional log parsing based on container type
  - MOV.AI application containers (backend, spawner, flow-initiator) use the `app_logs` parser
  - Other containers (redis, infrastructure) use the generic `docker` parser

### Log Format

MOV.AI application logs are parsed with the structured `app_logs` parser in the following format:

```
[LEVEL][YYYY-MM-DD HH:MM:SS][module][function][lineno]: [user_log:VALUE] MESSAGE
```

**Example:**
```
[INFO][2026-03-03 10:30:45][my_module][my_function][123]: [user_log:system] Application started successfully
```

**Parsed Fields:**
- `level`: Log level (INFO, WARNING, ERROR, DEBUG, etc.)
- `timestamp`: Log timestamp
- `module`: Module name
- `funcName`: Function name
- `lineno`: Line number
- `user_log`: User-defined log category for filtering
- `message`: Log message content

**Note:** Fields enclosed in square brackets may contain escaped closing brackets (`\]`) if needed.

### Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 24224 | TCP (Forward) | Log ingestion from applications |
| 24225 | TCP (Forward) | Metrics / notifications  ingestion |
| 2020 | HTTP | Health checks and metrics endpoint |

### Manager Configuration

Used on manager nodes. Configuration will typically include:

- **Output**: Loki endpoint at local `loki:3100` container.
- **Labels**: Includes `container_name`, `service`, `robot`, and `user_log` for filtering

### Worker Configuration

Used on worker nodes. Configuration will typically include:

- **Output**: Loki endpoint at manager node (e.g., `manager.company.com:3100`).
- **Labels**: Includes `container_name`, `service`, `robot`, and `user_log` for filtering


## Environment Variables

| Variable | Purpose | Example | Required |
|----------|---------|---------|----------|
| `FLUENT_BIT_CONFIG` | Path to Fluent Bit config | `/fluent-bit/etc/fluent-bit.conf` | No |
| `LOKI_HOST` | Loki server hostname | `loki-aggregator` | Yes (via config) |
| `LOKI_PORT` | Loki server port | `3100` | No |
| `APP_NAME` | Service name for log labeling | `log-agent` | No |
| `DEVICE_NAME` | Device/robot name for log labeling | `robot-01` | No |


## Related Services

- **Log Aggregator**: Process, index, and store logs (Loki-based)
- **Grafana**: Visualization and querying interface

## Support and Contributions

For issues, feature requests, or contributions, please refer to the [MOV.AI Contributing Guide](.github/CONTRIBUTING.md).

## Build

To build the Docker image locally:

```bash
docker build -t registry.cloud.mov.ai/qa/log-agent:latest -f docker/Dockerfile .
```

## License

[MOV.AI License](MOVAI_LICENSE.md)

## Changelog

See [CHANGELOG.md](.github/workflows/../../../CHANGELOG.md) for version history and release notes.
See [CHANGELOG.md](CHANGELOG.md) for version history and release notes.
