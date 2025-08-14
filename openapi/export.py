"""Export OpenAPI schema for MediaHub API."""
import json
import sys
from pathlib import Path

import yaml

# Ensure project root is in path
ROOT = Path(__file__).resolve().parent.parent
sys.path.append(str(ROOT))

from api.main import app


def main():
    schema = app.openapi()
    base = Path(__file__).resolve().parent
    json_path = base / "openapi.json"
    yaml_path = base / "openapi.yaml"
    json_path.write_text(json.dumps(schema, indent=2))
    yaml_path.write_text(yaml.safe_dump(schema, sort_keys=False))


if __name__ == "__main__":
    main()
