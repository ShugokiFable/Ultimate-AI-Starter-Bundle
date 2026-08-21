"""Same failure as C, with no diagnostics at all."""
import json
import os


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, "config.json"), encoding="utf-8") as fh:
        cfg = json.load(fh)
    try:
        retries = cfg["retry"]["max_attempts"]
    except Exception:
        print("Startup failed")
        raise SystemExit(1)
    print("started, retries=%s" % retries)


if __name__ == "__main__":
    main()
