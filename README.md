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
- **Parsing**: Multi-format log parsing with intelligent detection
  - `callback_logs`: Callback-based logs with dynamic tags (ui, node extraction)
  - `python_structured`: Python structured logs with tags field
  - `app_logs`: MOV.AI application logs (supports both with and without user_log field)
  - `docker`: Generic JSON Docker logs
- **Processing**: Lua filter for ANSI color code stripping and tag extraction before parsing

### Log Formats

The Log Agent supports multiple structured log formats:

#### 1. Callback Logs (with dynamic tags)
```
[LEVEL][YYYY-MM-DD HH:MM:SS][module][function][lineno]: [tag:value|tag:value|...] MESSAGE
```

**Example:**
```
[CRITICAL][2026-03-04 16:19:17][stress_logs_movai][test_callback][48]: [ui:True|node:robot_01] Callback logger critical for iteration=22
[INFO][2026-03-04 12:34:56][mymodule][my_function][42]: [ui:False] Standard callback message
```

**Parsed Fields (with Lua extraction):**
- `level`: Log level (INFO, WARNING, ERROR, CRITICAL, etc.)
- `timestamp`: Log timestamp
- `module`: Module name
- `funcName`: Function name
- `lineno`: Line number
- `tags`: Raw tags string (original format: `tag1:value1|tag2:value2`)
- `ui`: Extracted ui tag value (`True` or `False` only, nil if not present)
- `node`: Extracted node tag value (any string, nil if not present)
- `has_ui`: Boolean flag if ui tag exists with valid value
- `has_node`: Boolean flag if node tag exists
- `message`: Log message content

#### 2. Application Logs (MOV.AI format)
Supports both with and without user_log field in single parser.

**With user_log field:**
```
[LEVEL][YYYY-MM-DD HH:MM:SS][module][function][lineno]: [user_log:VALUE] MESSAGE
```

**Without user_log field:**
```
[LEVEL][YYYY-MM-DD HH:MM:SS][module][function][lineno]: MESSAGE
```

**Example:**
```
[INFO][2026-03-03 10:30:45][my_module][my_function][123]: [user_log:system] Application started successfully
[WARNING][2026-03-03 23:30:41][spawner][<module>][74]: Robot default-robot warning signal
```

**Parsed Fields:**
- `level`: Log level (INFO, WARNING, ERROR, DEBUG, etc.)
- `timestamp`: Log timestamp
- `module`: Module name
- `funcName`: Function name
- `lineno`: Line number
- `user_log`: User-defined log category (optional, empty if not present)
- `message`: Log message content

#### 3. Python Structured Logs
```
[levelname][asctime][module][funcName][tags][lineno]: message
```

**Example:**
```
[INFO][2026-03-04 12:34:56,123][mymodule][my_function][device:test][42]: Something happened
```

**Parsed Fields:**
- `levelname`: Log level
- `asctime`: Timestamp with milliseconds
- `module`: Module name
- `funcName`: Function name
- `tags`: Tag field (device:test format)
- `lineno`: Line number
- `message`: Log message content

#### 4. Docker (JSON format)
Generic JSON logs from Docker containers.

**Processing Optimizations:**
- ANSI color codes automatically stripped before parsing (reduces noise in logs)
- Lua filter only checks for ANSI sequences if escape character present
- Consolidated `app_logs` parser handles both formats with optional user_log in single regex
- Direct tag extraction for callback_logs (targeted pattern matching for ui/node tags only)
- ~75-80% CPU reduction for typical log processing compared to non-optimized approach

### Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 24224 | TCP (Forward) | Log ingestion from applications |
| 24225 | TCP (Forward) | Metrics / notifications  ingestion |
| 2020 | HTTP | Health checks and metrics endpoint |

### Loki Labels and Output

Parsed log fields are exported as Loki labels based on configuration:

**Standard Labels:**
- `source`: Always `docker`
- `container_name`: Container identifier
- `service`: Service name
- `robot`: Device/robot identifier
- `level`: Log level (from parsers)

**Extract Labels (when available):**
- `user_log`: User-defined category from app_logs
- `ui`: UI indicator from callback_logs (True/False)
- `node`: Node identifier from callback_logs
- `has_ui`: Boolean flag for callback logs with ui tag
- `has_node`: Boolean flag for callback logs with node tag
- `module`: Module name
- `funcName`: Function name
- `lineno`: Line number
- `tags`: Raw tags from python_structured or callback_logs

**Manager Configuration:**
- **Output**: Loki endpoint at local `loki:3100` container
- **Labels**: Full set as described above

**Worker Configuration:**
- **Output**: Loki endpoint to manager node (e.g., `manager.company.com:3100`)
- **Labels**: Full set as described above


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

## Testing

This project includes a full local testing environment with Docker Compose that brings up a complete logging stack.

### Test Environment Setup

The `tests/` directory contains:

- **docker-compose.yml**: Manager node environment (includes Loki, Grafana, full MOV.AI stack)
- **docker-compose-worker.yml**: Worker node environment (simulates distributed setup)
- **stress_logs.py**: Generate test logs using standard Python logging
- **stress_logs_movai.py**: Generate test logs using MOV.AI structured format

### Running Local Tests

#### 1. Start the Full Stack (Manager)

```bash
cd tests
mkdir -p manager_userspace manager_shared manager_logs
sudo chmod 777 manager_userspace manager_shared manager_logs

mkdir -p worker_userspace worker_shared worker_logs
sudo chmod 777 worker_userspace worker_shared worker_logs

docker compose -f docker-compose.yml up -d
```

This brings up:
- **Fluent Bit** (port 24224 for logs, 24225 for metrics)
- **Loki** (port 3100 for log aggregation)
- **Grafana** (port 3000 for visualization)
- **Redis** (caching)
- **Backend** (MOV.AI backend services)
- **Spawner** (MOV.AI flow engine)

#### 2. Generate Test Logs

From the spawner container:

```bash
# Using MOV.AI logging format
docker exec spawner-manager-test python3 /opt/mov.ai/scripts/stress_logs_movai.py

# Using standard Python logging
docker exec spawner-manager-test python3 /opt/mov.ai/scripts/stress_logs.py
```

Or configure with environment variables:

```bash
# Set custom iterations and interval
docker exec -e ITERATIONS=50 -e LOG_INTERVAL_SEC=0.5 spawner-manager-test \
  python3 /opt/mov.ai/tests/stress_logs_movai.py
```

#### 3. View Logs in Grafana

1. Open [Grafana](http://200.168.1.254:3000)
   - Username: `admin`
   - Password: `admin`

2. Navigate to **Explore** → Select **Loki** as datasource

3. Query logs:
   ```
   {service="backend"} | json | level="INFO"
   ```

#### 4. Cleanup

```bash
docker compose -f docker-compose.yml down --volumes --remove-orphans
```

### Test Configuration

**Environment Variables for Test Scripts:**

| Variable | Purpose | Default | Notes |
|----------|---------|---------|-------|
| `ROBOT_ID` | Robot/device identifier | `DEVICE_NAME` or `default-robot` | Sets log label for filtering |
| `APP_NAME` | Application name | `movai-stress-logs` or `python-stress-logs` | Logger instance name |
| `ITERATIONS` | Number of log iterations | `20` (movai) or `0` (python) | Set to `0` for infinite |
| `LOG_INTERVAL_SEC` | Seconds between log entries | `1.0` (movai) or `0.1` (python) | Controls log volume |

### Testing Log Format Parsing

The test scripts validate:

- **Callback format** (`stress_logs_movai.py` with ui/node tags):
  ```
  [CRITICAL][2026-03-04 16:19:17][module][function][lineno]: [ui:True|node:robot_01] MESSAGE
  ```
  Tests callback_logs parser with tag extraction via Lua filter

- **MOV.AI format** (`stress_logs_movai.py` standard):
  ```
  [INFO][YYYY-MM-DD HH:MM:SS][module][function][lineno]: [user_log:VALUE] MESSAGE
  ```
  Tests app_logs parser with user_log field extraction

- **Standard format** (`stress_logs.py`):
  ```
  YYYY-MM-DD HH:MM:SS | LEVEL | APP_NAME | MESSAGE
  ```
  Tests generic JSON parsing via docker parser

### Verifying Parser Configuration

Query Loki to verify fields are properly extracted:

```promql
# Check callback_logs with ui and node tags extracted
{service="spawner", has_ui="true"} | json | ui="True"

# Filter by node (robot) from callback logs
{service="spawner", has_node="true", node="robot_01"}

# Check user_log label from app_logs parser
{user_log=~"system|.*"}

# Count logs by level and ui flag across all services
count by (level, ui) ({service=~"backend|spawner"} | json | has_ui="true")

# Find all callback logs with ui:True
{has_ui="true", ui="True"} | json

# Find logs from specific node
{has_node="true", node="robot_01"}
```

### Troubleshooting Tests

If logs aren't appearing in Loki:

1. **Check Fluent Bit logs**:
   ```bash
   docker logs fluent-bit-manager-test
   ```

2. **Verify connectivity**:
   ```bash
   docker exec fluent-bit-manager-test curl -s http://localhost:2020/api/v1/health
   ```

3. **Check docker driver configuration**:
   ```bash
   docker inspect spawner-manager-test | grep -A 10 LogConfig
   ```

## License

[MOV.AI License](MOVAI_LICENSE.md)

## Changelog

See [CHANGELOG.md](.github/workflows/../../../CHANGELOG.md) for version history and release notes.
See [CHANGELOG.md](CHANGELOG.md) for version history and release notes.
