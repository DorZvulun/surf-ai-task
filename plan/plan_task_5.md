# Task 5 Plan: Dockerfile for Python App

## Context
Task 4 produced `app/main.py` (Flask, port 8080) and `app/requirements.txt` (flask==3.1.1).
Task 5 packages that app into a Docker image. CLAUDE.md explicitly says: no multi-stage,
keep it simple and small. The image will be tagged `$DOCKERHUB_USERNAME/ironman-web-app:latest`
and pushed in Task 6.

## File to Create

### `app/Dockerfile`
```dockerfile
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

EXPOSE 8080

CMD ["python3", "main.py"]
```

Key decisions:
- `python:3.12-slim` — current stable, minimal footprint, no alpine (avoids musl/wheel issues)
- `COPY requirements.txt` before `COPY main.py` — layer cache: dep install only re-runs when requirements change
- `--no-cache-dir` — reduces image size
- `CMD` not `ENTRYPOINT` — keeps the container easy to override for debugging
- No non-root user — CLAUDE.md says keep it simple; this is a local dev/demo task

## Verification
```bash
cd app
docker build -t ironman-web-app:latest .
docker run --rm -p 8080:8080 ironman-web-app:latest &
sleep 1
curl -s localhost:8080
# Expected: {"app":"python-app","pod_ip":"unknown","pod_name":"unknown"}
docker stop $(docker ps -q --filter ancestor=ironman-web-app:latest)
```
