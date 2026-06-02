# Task 4 Plan: Python Flask App

## Context
Phase 2 of the candidate task. The `app/` directory is empty (only `.gitkeep`).
Need to create the custom Python web app that will be containerized in Task 5 and
pushed to Docker Hub in Task 6. App reads pod metadata injected by Kubernetes
Downward API and returns it as JSON.

## Files to Create

### `app/requirements.txt`
```
flask==3.1.1
```
Pin to a recent stable Flask version. No other deps needed.

### `app/main.py`
```python
import os
from flask import Flask, jsonify

app = Flask(__name__)

@app.route("/")
def index():
    return jsonify(
        pod_name=os.environ.get("POD_NAME", "unknown"),
        pod_ip=os.environ.get("POD_IP", "unknown"),
        app="python-app",
    )

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
```

Key decisions:
- `host="0.0.0.0"` — required so the container port is reachable from outside
- Graceful fallback to `"unknown"` for local dev (env vars not injected outside k8s)
- Single route `/` — strip-prefix middleware in Traefik removes `/python-app` before forwarding
- `jsonify` preserves key order and sets `Content-Type: application/json`

## Verification
```bash
cd app
pip install -r requirements.txt
python main.py &
curl -s localhost:8080 | python3 -m json.tool
# Expected: {"pod_name": "unknown", "pod_ip": "unknown", "app": "python-app"}
kill %1
```
