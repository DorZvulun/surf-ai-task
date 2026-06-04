# Engineering Notes

## pvotal-tech/k3d provider v0.0.7 — cluster creation bug

**Symptom**: `terraform apply` fails with:

```
Error: Failed Cluster Start: Failed to start server k3d-surf-cluster-server-0:
Node k3d-surf-cluster-server-0 failed to get ready: error waiting for log line
`k3s is up and running` from node 'k3d-surf-cluster-server-0': stopped returning
log lines: node k3d-surf-cluster-server-0 is running=true in status=restarting
```

**Root cause**: The provider embeds a `k3d v5-dev` library (visible via the
`k3d.version:v5-dev` Docker label on containers it creates). This dev build omits
`--privileged` from the Docker HostConfig when starting k3s server containers.
Without it, k3s cannot mount cgroupfs and exits immediately (ExitCode=1):

```
level=fatal msg="failed to evacuate root cgroup: mkdir /sys/fs/cgroup/init: read-only file system"
```

The k3d CLI (v5.8.3) sets `--privileged` correctly and creates clusters without issue.
The provider also does not implement the `terraform import` command for `k3d_cluster`,
so there is no way to reconcile a CLI-created cluster with the resource.

**Workaround**: Use `data "k3d_cluster"` (provider reads existing cluster state fine)
and manage the cluster lifecycle via the Makefile (`k3d cluster create / delete`).
`infra/cluster.tf` uses the data source; see `Makefile` for the `cluster-create` /
`cluster-delete` targets wired into `apply` and `destroy`.


# TESTS

There are three levels of testing, ordered by speed:

  ---
  1. Lint only — fastest, no cluster needed (~1 min) [DONE]

  Validates the Terraform and Helm portions of the lint-and-validate job:
  terraform -chdir=infra fmt -check
  terraform -chdir=infra init
  terraform -chdir=infra validate
  helm lint gitops/chart/

  ---
  2a. Full local CI with act (~10-15 min) [DONE]

  Runs the entire workflow in Docker, simulating a GitHub push:
  act push --secret-file .secrets

  Caveats:
  - Needs Docker running and .secrets populated with real Docker Hub creds
  - dorny/paths-filter in act treats all files as changed (no real git base to diff against), so both jobs will run — that's
  fine for testing
  - The deploy job creates a real k3d cluster inside Docker-in-Docker, which requires the runner to support it (act does with
  the right image)

  ---
  2b. Full CI in Github Actions [DONE]

  Runs the entire workflow in Github Actions. 
  - needs secrets for Docker hub configured in the repo. 

  ---
  3. Manual end-to-end — most reliable (~10 min) [ ]

  Skips act entirely and runs the same steps the CI would:
  make build          # only if app/ changed
  make init
  make apply          # creates cluster + terraform apply
  kubectl -n argocd wait --for=condition=Synced application/ironman-web-app --timeout=120s
  make test
  make destroy

  This is the most reliable local test because it uses your actual Docker and k3d environment, not Docker-in-Docker.

  ---
  4. Push to GitHub — ground truth [ ]

  Push to main and watch the Actions tab. This is the only way to confirm the path filter logic works correctly (e.g. that a
  docs-only commit actually skips the deploy job).

  ---
  Recommended order: Run option 1 first to catch any config issues quickly, then option 3 to verify the full stack, then push
  to GitHub to confirm the workflow triggers correctly.