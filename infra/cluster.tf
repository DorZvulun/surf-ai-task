# Provider bug prevents using the resource — see notes.md for details.
# Cluster lifecycle is managed via the Makefile (k3d CLI).
data "k3d_cluster" "cluster" {
  name = "surf-cluster"
}
