# Task 6 Plan: Build and Push to Docker Hub

## Context
Tasks 4 and 5 produced a working Flask app and Dockerfile in `app/`. Task 6 publishes
the image to Docker Hub so it can be pulled by Kubernetes later. No new files are
created — this is a pure execution task using credentials from the gitignored `.secrets`
file. The Makefile `build` target (Task 11) will wrap these same commands later.

## No files to create or modify

This task is entirely operational. All code is already in place from Tasks 4–5.

## Steps to execute

```bash
# 1. Load credentials
source .secrets          # exports DOCKERHUB_USERNAME, DOCKERHUB_TOKEN

# 2. Authenticate with Docker Hub
echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin

# 3. Build with the correct remote tag
docker build -t "$DOCKERHUB_USERNAME/ironman-web-app:latest" ./app

# 4. Push
docker push "$DOCKERHUB_USERNAME/ironman-web-app:latest"
```

## Verification
After push completes, confirm the image is live:
```bash
docker manifest inspect "$DOCKERHUB_USERNAME/ironman-web-app:latest"
# or visit: https://hub.docker.com/r/$DOCKERHUB_USERNAME/ironman-web-app
```
