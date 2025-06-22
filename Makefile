SHELL := /bin/bash
.DEFAULT_GOAL := help

INVENTORY ?= inventories/dev/hosts.yml
PLAYBOOK  ?= playbooks/site.yml
LIMIT     ?=
TAGS      ?=
ROLES     := baseline docker_host nginx haproxy node_exporter backup

# Turn the optional variables into flags only when they are actually set, so
# `ansible-playbook` never receives an empty `--limit ''`.
ANSIBLE_FLAGS := -i $(INVENTORY)
ifneq ($(strip $(LIMIT)),)
ANSIBLE_FLAGS += --limit $(LIMIT)
endif
ifneq ($(strip $(TAGS)),)
ANSIBLE_FLAGS += --tags $(TAGS)
endif

.PHONY: help deps lint syntax test check deploy molecule clean

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[1m%-12s\033[0m %s\n", $$1, $$2}'

deps: ## Install the collections the roles depend on
	ansible-galaxy collection install -r requirements.yml

lint: ## Run yamllint and ansible-lint
	yamllint .
	ansible-lint

syntax: ## Parse every playbook without touching a host
	@for playbook in playbooks/*.yml; do \
		echo "==> $$playbook"; \
		ansible-playbook -i $(INVENTORY) --syntax-check "$$playbook" || exit 1; \
	done

test: ## Run the molecule scenario of every role
	@for role in $(ROLES); do \
		echo "==> molecule test: $$role"; \
		( cd roles/$$role && molecule test ) || exit 1; \
	done

molecule: ## Run one role's molecule scenario, e.g. make molecule ROLE=nginx
	@test -n "$(ROLE)" || { echo "usage: make molecule ROLE=<role>"; exit 2; }
	cd roles/$(ROLE) && molecule test

check: ## Dry run against the inventory (no changes applied)
	ansible-playbook $(ANSIBLE_FLAGS) --check --diff $(PLAYBOOK)

deploy: ## Apply the playbook against the inventory
	ansible-playbook $(ANSIBLE_FLAGS) $(PLAYBOOK)

clean: ## Remove local caches and molecule leftovers
	rm -rf .cache .ansible
	@for role in $(ROLES); do ( cd roles/$$role && molecule destroy >/dev/null 2>&1 || true ); done
