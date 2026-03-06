#!/usr/bin/env python3

import logging as std_logging
import os
from pathlib import Path
import sys
import time
import uuid

from movai_core_shared.logger import Log as logging

# --- Configuration ---
ROBOT_ID = os.getenv("DEVICE_NAME", "default-robot")
APP_NAME = os.getenv("APP_NAME", "movai-stress-logs")
LOG_INTERVAL_SEC = float(os.getenv("LOG_INTERVAL_SEC", "1.0"))
ITERATIONS = int(os.getenv("ITERATIONS", "200"))  # set to 0 for infinite

# --- MOVAI multiple Logs Test run ---

user_logs_logger = logging.get_user_logger(APP_NAME)
user_logs_logger.setLevel("DEBUG")

callback_logger = logging.get_callback_logger(APP_NAME, "stress_logs_movai", "test_callback")
callback_logger.setLevel("DEBUG")

run_id = str(uuid.uuid4())[:8]

user_logs_logger.info("Starting Fluent Bit / Loki validation run")
user_logs_logger.info("Run ID=%s Robot=%s PID=%s", run_id, ROBOT_ID, os.getpid())

callback_logger.info("Callback logger initialized for run_id=%s", run_id)

i = 0
while ITERATIONS == 0 or i < ITERATIONS:
    # user_logs_logger.info("Robot %s started iteration=%d run_id=%s", ROBOT_ID, i, run_id)
    # user_logs_logger.warning("Robot %s warning signal iteration=%d", ROBOT_ID, i)

    # callback_logger.debug("Callback logger message for iteration=%d", i, ui=False)
    # callback_logger.info("Callback logger info for iteration=%d", i, ui=False)
    # callback_logger.warning("Callback logger warning for iteration=%d", i, ui=False)
    # callback_logger.error("Callback logger error for iteration=%d", i, ui=False)
    callback_logger.critical("Callback logger critical for iteration=%d", i)

    # callback_logger.debug("UI - Callback logger message for iteration=%d", i, ui=True)
    # callback_logger.info("UI - Callback logger info for iteration=%d", i, ui=True)
    # callback_logger.warning("UI - Callback logger warning for iteration=%d", i, ui=True)
    # callback_logger.error("UI - Callback logger error for iteration=%d", i, ui=True)
    callback_logger.critical("UI - Callback logger critical for iteration=%d", i, ui=True)

    if i % 5 == 0:
        user_logs_logger.error("Robot %s simulated error iteration=%d", ROBOT_ID, i)
        callback_logger.error("Callback logger error for iteration=%d", i)

    time.sleep(LOG_INTERVAL_SEC)
    i += 1

user_logs_logger.info("Completed Fluent Bit / Loki validation run run_id=%s", run_id)
callback_logger.info("Callback logger completed for run_id=%s", run_id)

