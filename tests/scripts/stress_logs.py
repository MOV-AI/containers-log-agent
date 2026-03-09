#!/usr/bin/env python3

import logging
import os
import sys
import time
import uuid

# --- Configuration ---
ROBOT_ID = os.getenv("DEVICE_NAME", "default-robot")
APP_NAME = os.getenv("APP_NAME", "python-stress-logs")
LOG_INTERVAL_SEC = float(os.getenv("LOG_INTERVAL_SEC", "0.1"))
ITERATIONS = int(os.getenv("ITERATIONS", "0"))  # set to 0 for infinite

# --- Logger setup ---
logger = logging.getLogger(APP_NAME)
logger.setLevel(logging.DEBUG)

handler = logging.StreamHandler(sys.stdout)
formatter = logging.Formatter(
    fmt="%(asctime)s.%(msecs)03d | %(levelname)s | %(name)s | %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
)
handler.setFormatter(formatter)

logger.addHandler(handler)
logger.propagate = False

# --- Test run ---
run_id = str(uuid.uuid4())[:8]

logger.info("Starting Fluent Bit / Loki validation run")
logger.info("Run ID=%s Robot=%s PID=%s", run_id, ROBOT_ID, os.getpid())

i = 0
while ITERATIONS == 0 or i < ITERATIONS:
    logger.info("Robot %s started iteration=%d run_id=%s", ROBOT_ID, i, run_id)
    logger.warning("Robot %s warning signal iteration=%d", ROBOT_ID, i)

    if i % 5 == 0:
        logger.error("Robot %s simulated error iteration=%d", ROBOT_ID, i)

    time.sleep(LOG_INTERVAL_SEC)
    i += 1

logger.info("Completed Fluent Bit / Loki validation run run_id=%s", run_id)
