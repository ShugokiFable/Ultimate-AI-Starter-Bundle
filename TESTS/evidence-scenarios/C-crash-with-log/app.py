"""Reads a config and starts. Crashes on a machine where the config is old."""
import json
import logging
import os
import sys

LOG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "app.log")
logging.basicConfig(
    filename=LOG, level=logging.DEBUG, filemode="w",
    format="%(asctime)s %(levelname)-7s %(name)s %(message)s",
)
log = logging.getLogger("app")


def load_config(path):
    log.info("startup version=1.4.0 config=%s", path)
    with open(path, encoding="utf-8") as fh:
        cfg = json.load(fh)
    log.debug("config keys: %s", sorted(cfg))
    return cfg


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    cfg = load_config(os.path.join(here, "config.json"))
    try:
        retries = cfg["retry"]["max_attempts"]
    except KeyError:
        log.error("config is from before 1.3: 'retry.max_attempts' is missing; "
                  "found retry=%r. Migrate with tools/migrate_config.py",
                  cfg.get("retry"))
        raise
    log.info("ready, retries=%s", retries)
    print("started")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        log.exception("startup failed")
        print("Startup failed. See app.log", file=sys.stderr)
        sys.exit(1)
