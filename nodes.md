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
