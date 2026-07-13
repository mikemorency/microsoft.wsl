# Optional extra args for ansible-test (leave unset for full suite)
SANITY_TARGETS ?=

COLLECTION_ROOT ?= $(HOME)/.ansible/collections/ansible_collections/microsoft/wsl

# setup commands
.PHONY: upgrade-collections
upgrade-collections:
	ansible-galaxy collection install --upgrade -p ~/.ansible/collections .

tests/integration/inventory.winrm:
	chmod +x ./tests/integration/generate_inventory.sh; \
	./tests/integration/generate_inventory.sh


.PHONY: install-integration-reqs
install-integration-reqs:
		pip install -r tests/integration/requirements.txt; \
		ansible-galaxy collection install --upgrade -p ~/.ansible/collections -r tests/integration/requirements.yml

# test commands
.PHONY: linters
linters:
	ansible-lint;

.PHONY: sanity
sanity: upgrade-collections
	cd $(COLLECTION_ROOT); \
	ansible-test sanity -v --color --coverage --junit \
		--docker default $(SANITY_TARGETS)

.PHONY: integration
integration: tests/integration/inventory.winrm install-integration-reqs upgrade-collections
	cp tests/integration/inventory.winrm $(COLLECTION_ROOT)/tests/integration/inventory.winrm; \
	cd $(COLLECTION_ROOT); \
	ansible --version; \
	ansible-test --version; \
	ANSIBLE_COLLECTIONS_PATH=$(COLLECTION_ROOT)/../.. ansible-galaxy collection list; \
	ANSIBLE_ROLES_PATH=$(COLLECTION_ROOT)/tests/integration/targets \
		ANSIBLE_COLLECTIONS_PATH=$(COLLECTION_ROOT)/../.. \
		ansible-test windows-integration $(CLI_ARGS);
