variable "repo_url" {
  description = "GitHub repository URL watched by ArgoCD"
  type        = string
}

variable "docker_username" {
  description = "Docker Hub username (set via TF_VAR_docker_username — never hardcoded)"
  type        = string
  default     = ""
}
