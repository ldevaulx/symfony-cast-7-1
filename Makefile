# Documentation GNU Make :
# https://www.gnu.org/software/make/manual/make.html
# Par défaut, les commandes sont lancées avec sh (et non bash)

# ===================
# Variables à définir
# ===================

NAMESPACE=minikube-skeleton
HELM_NAME   := minikube-skeleton

PHP_SOURCES := ./src/ ./public/

HELM_DIR            := deploy
HELM_VALUES_DEV     := values_dev.yaml
HELM_VALUES_STAGING := values_staging.yaml
POD_SEARCH          := $(HELM_NAME)

BUILD_DIR   := build
DOCKERFILE  := php.dockerfile
REPOSITORY  := 444963888884.dkr.ecr.eu-west-3.amazonaws.com/prod/minikube-skeleton

DEPLOY_TAG_STAGING    := deploy_staging
DEPLOY_TAG_PRODUCTION := deploy_prod

LOGS_S3_BUCKET      := passman-firmwares
LOGS_S3_PATH        := codebuild-logs

# =============================================================================
# Variables pouvant être surchargées par des variables d'environnement externes
# =============================================================================

CI        ?= 0
BUILD_TAG ?=

CODEBUILD_BUILD_SUCCEEDING ?= 0
CODEBUILD_BUILD_URL        ?=
CODEBUILD_WEBHOOK_TRIGGER  ?=
CODEBUILD_SOURCE_REPO_URL  ?=
CODEBUILD_LOG_PATH         ?=

# ====================
# Traitement préalable
# ====================

# Definit la cible par défaut
# Sinon, la première cible trouvée est exécutée
.DEFAULT_GOAL := help

# Nom du fichier Makefile (normalement, "Makefile")
TARGETS := $(MAKEFILE_LIST)

# Test présence namespace et récupération pod si environnement dev (CI=0)
ifeq ($(CI),0)
	NAMESPACE_PRESENT := $(shell kubectl get namespace     $(NAMESPACE) -o name --ignore-not-found | wc -l)
	POD_NAME          := $(shell kubectl get pods       -n $(NAMESPACE) -o name | grep $(POD_SEARCH) | cut -d'/' -f2)
	DEPLOYMENT_NAME   := $(shell kubectl get deployment -n $(NAMESPACE) -o name | grep $(POD_SEARCH) | cut -d'/' -f2)
	EXEC_BUILD        := kubectl exec -n $(NAMESPACE) $(POD_NAME) -it --
else
	EXEC_BUILD :=
endif

# Message en fonction de l'état du build
ifeq ($(CI),0)
	GOOGLE_CHAT_MESSAGE :=
else
	# Formattage : https://developers.google.com/hangouts/chat/reference/message-formats/basic
	DETAILS_BUILD := \n<$(CODEBUILD_BUILD_URL)|Logs CodeBuild>\n<https://$(LOGS_S3_BUCKET).s3.eu-west-3.amazonaws.com/$(LOGS_S3_PATH)/$(CODEBUILD_LOG_PATH).gz|Logs S3>\nReference Git : $(CODEBUILD_WEBHOOK_TRIGGER)\nRepository Git : <$(CODEBUILD_SOURCE_REPO_URL)|$(CODEBUILD_SOURCE_REPO_URL)>
	ifeq ($(CODEBUILD_BUILD_SUCCEEDING),1)
		# Build OK
		GOOGLE_CHAT_MESSAGE := *Build OK* $(DETAILS_BUILD)
	else
		# Erreur build
		GOOGLE_CHAT_MESSAGE := *ERREUR Build* $(DETAILS_BUILD)
	endif
endif

# ======
# Help !
# ======

# Astuce d'auto-documentation
# https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
.PHONY: help
help: ## DEV   : This help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(TARGETS) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

# ===========
# Gestion pod
# ===========

.PHONY: pod-infos
pod-infos: ## DEV   : Pod namespace and name
	@echo "NAMESPACE         = $(NAMESPACE)"
	@echo "NAMESPACE_PRESENT = $(NAMESPACE_PRESENT)"
	@echo "POD_NAME          = $(POD_NAME)"
	@echo "DEPLOYMENT_NAME   = $(DEPLOYMENT_NAME)"

.PHONY: pod-shell
pod-shell: ## DEV   : Launch shell in pod
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -it -- /bin/bash

.PHONY: pod-logs
pod-logs: ## DEV   : Tail logs of the pod
	kubectl logs -n $(NAMESPACE) $(POD_NAME) --follow

.PHONY: pod-describe
pod-describe: ## DEV   : Describe the pod
	kubectl describe pod -n $(NAMESPACE) $(POD_NAME)

.PHONY: pod-restart
pod-restart: ## DEV   : Restart the pod using scaling
	kubectl scale --replicas=0 -n $(NAMESPACE) deployment/$(DEPLOYMENT_NAME)
	kubectl scale --replicas=1 -n $(NAMESPACE) deployment/$(DEPLOYMENT_NAME)

# ============
# Gestion helm
# ============

.PHONY: helm-install
helm-install: ## DEV   : Install/update the application with Helm
# Creation du namespace si inexistant
# Attente pour que registry-creds ait le temps d'ajouter les tokens au namespace
ifeq ($(NAMESPACE_PRESENT),0)
	kubectl create namespace $(NAMESPACE)
	while ! kubectl get -n $(NAMESPACE) secret/awsecr-cred ; do sleep 1 ; done
endif
# Installation
	helm upgrade -n $(NAMESPACE) --install $(HELM_NAME) -f $(HELM_DIR)/$(HELM_VALUES_DEV) $(HELM_DIR)

.PHONY: helm-uninstall
helm-uninstall: ## DEV   : Remove the application with Helm
# Desinstallation
	helm uninstall -n $(NAMESPACE) $(HELM_NAME)
# Information pour supprimer le namespace
	@echo "Delete namespace with: kubectl delete namespace $(NAMESPACE)"

.PHONY: helm-install-staging
helm-install-staging: ## DEV   : Test the staging application locally (the dev version shouldn't be installed)
# Creation du namespace si inexistant
# Attente pour que registry-creds ait le temps d'ajouter les tokens au namespace
ifeq ($(NAMESPACE_PRESENT),0)
	kubectl create namespace $(NAMESPACE)
	while ! kubectl get -n $(NAMESPACE) secret/awsecr-cred ; do sleep 1 ; done
endif
# Installation
	helm upgrade -n $(NAMESPACE) --install $(HELM_NAME) -f $(HELM_DIR)/$(HELM_VALUES_STAGING) --set Ingress.Host=minikube $(HELM_DIR)


# ===========
# Application
# ===========

.PHONY: app-packages
app-packages: ## DEV   : Check packages and install missing dependencies
	$(EXEC_BUILD) composer install

.PHONY: app-test-cs
app-test-cs: ## DEV+CI: Run code style checks
	$(EXEC_BUILD) ./vendor/bin/phpcs

.PHONY: app-fix-cs
app-fix-cs: ## DEV+CI: Run code style fixes
	$(EXEC_BUILD) phpcbf

.PHONY: app-test-stan
app-test-stan: ## DEV+CI: Run static analysis
	$(EXEC_BUILD) ./vendor/bin/phpstan analyze --debug --memory-limit 512M --level 7 $(PHP_SOURCES)

.PHONY: app-serve
app-serve: ## DEV   : Launch PHP-FPM daemon
	$(EXEC_BUILD) php-fpm

# ===============
# Container image
# ===============

.PHONY: container-auth
container-auth: ##     CI: Container registry authentication
ifneq ($(BUILD_TAG),)
	@echo "BUILD_TAG=$(BUILD_TAG)"
	$(EXEC_BUILD) `aws ecr get-login --no-include-email | sed -e 's/docker login/buildah login/g' | sed -e 's|https://||g'`
else
	@echo "Aucun BUILD_TAG !"
endif

.PHONY: container-build
container-build: ##     CI: Build a container from the application
ifneq ($(BUILD_TAG),)
	@echo "BUILD_TAG=$(BUILD_TAG)"
	$(EXEC_BUILD) buildah build-using-dockerfile -f $(BUILD_DIR)/$(DOCKERFILE) -t $(REPOSITORY):$(BUILD_TAG) .
else
	@echo "Aucun BUILD_TAG !"
endif

.PHONY: container-push
container-push: ##     CI: Push the container to the registry
ifneq ($(BUILD_TAG),)
	@echo "BUILD_TAG=$(BUILD_TAG)"
	$(EXEC_BUILD) buildah push $(REPOSITORY):$(BUILD_TAG)
else
	@echo "Aucun BUILD_TAG !"
endif

# =====================
# Build new application
# =====================

.PHONY: tag-build
tag-build: ## DEV   : Build a version with a timestamped tag
	@export TIMESTAMP=build_`date +"%G-%m-%d_%Hh%M"`; \
	echo TAG = $$TIMESTAMP; \
	git tag $$TIMESTAMP; \
	git push origin $$TIMESTAMP;

# ===============
# Deployment tags
# ===============

.PHONY: tag-deploy
tag-deploy: ## DEV   : Set tag to current HEAD to deploy in production
	@export TIMESTAMP=deploy_`date +"%G-%m-%d_%Hh%M"`; \
	echo TAG = $$TIMESTAMP; \
	git tag $$TIMESTAMP; \
	git push origin $$TIMESTAMP;

