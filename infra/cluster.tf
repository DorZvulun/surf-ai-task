# pvotal-tech/k3d provider v0.0.7 embeds a k3d v5-dev library that omits
# --privileged when starting k3s server containers, causing immediate death:
#   "failed to evacuate root cgroup: mkdir /sys/fs/cgroup/init: read-only file system"
# The resource cannot provision the cluster; lifecycle is handled by the Makefile
# (k3d cluster create / delete). This data source reads the running cluster so
# downstream modules can depend on it and to expose the kubeconfig for outputs.
data "k3d_cluster" "cluster" {
  name = "surf-cluster"
}
