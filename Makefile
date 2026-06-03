include .secrets
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
	sed -i '' 's|repository:.*|repository: $(IMAGE)|' gitops/apps/python-app/values.yaml
	git add gitops/apps/python-app/values.yaml
	git diff --cached --quiet || git commit -m "[ci] update python-app image repository"
	git push || true

init:
	terraform -chdir=infra init

plan:
	terraform -chdir=infra plan

apply: cluster-create
	terraform -chdir=infra apply -auto-approve

destroy:
	terraform -chdir=infra destroy -auto-approve
	$(MAKE) cluster-delete

test:
	@echo "--- python-app ---" && curl -fsL localhost/python-app && echo
	@echo "--- echo-app ---"   && curl -fsL localhost/echo-app   && echo
	@echo "--- podinfo ---"    && curl -fsL localhost/podinfo     && echo

all: build init apply test
