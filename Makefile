-include .secrets
export

TF_VAR_docker_username := $(DOCKERHUB_USERNAME)
IMAGE := $(DOCKERHUB_USERNAME)/ironman-web-app

.PHONY: cluster-create cluster-delete build init plan apply destroy test all

cluster-create:
	k3d cluster create --config k3d-config.yaml

cluster-delete:
	k3d cluster delete surf-cluster

build:
	docker build -t $(IMAGE):latest app/
	docker push $(IMAGE):latest
	sed -i '' 's|repository:.*|repository: $(IMAGE)|' gitops/apps/ironman-web-app/values.yaml
	git add gitops/apps/ironman-web-app/values.yaml
	git diff --cached --quiet || git commit -m "[ci] update ironman-web-app image repository"
	git push || true

init:
	terraform -chdir=infra init

plan:
	terraform -chdir=infra plan

apply: cluster-create
	@echo "Waiting for Traefik CRD to be established..." && until kubectl wait --for=condition=established crd/ingressroutes.traefik.io --timeout=10s 2>/dev/null; do sleep 3; done
	terraform -chdir=infra apply -auto-approve -target=kubernetes_namespace.argocd -target=helm_release.argocd
	terraform -chdir=infra apply -auto-approve

destroy:
	terraform -chdir=infra destroy -auto-approve
	$(MAKE) cluster-delete

test:
	@echo "--- ironman-web-app ---" && curl -fsL localhost/ironman-web-app && echo
	@echo "--- echo-app ---"   && curl -fsL localhost/echo-app   && echo
	@echo "--- podinfo ---"    && curl -fsL localhost/podinfo     && echo

all: build init apply test
