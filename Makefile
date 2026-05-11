PROVIDER ?= upcloud
ENV      ?= prod

TF_ROOT       := terraform/providers/$(PROVIDER)
ANSIBLE_DIR   := ansible
SECRETS_FILE  ?= /tmp/vpn-$(ENV).secrets.yaml
SOPS_FILE     ?= $(HOME)/.config/vpn-provision/$(ENV).secrets.sops.yaml
TFVARS        := $(TF_ROOT)/environments/$(ENV).tfvars
TFPLAN        := $(TF_ROOT)/$(ENV).tfplan

export ANSIBLE_CONFIG := $(ANSIBLE_DIR)/ansible.cfg

.PHONY: help init validate plan apply inventory wait decrypt dry-run deploy verify clean \
        rollback-xray rollback-config rotate-credentials check-prereqs \
        destroy backup-state burn-check diff-secrets emit-singbox install-hooks \
        molecule-test smoke-test validate-target scan-targets blue-green \
        spot-check-secrets bootstrap-secrets probe-asn emit-qr check-certs \
        audit-permissions asn-drift

help:
	@echo "vpn-deploy Makefile"
	@echo ""
	@echo "Variables (override on command line):"
	@echo "  PROVIDER  current: $(PROVIDER)  (upcloud | hetzner | vultr)"
	@echo "  ENV       current: $(ENV)       (prod | staging)"
	@echo ""
	@echo "Targets:"
	@echo "  check-prereqs  Verify required CLI tools are installed"
	@echo "  init           terraform init in $(TF_ROOT)"
	@echo "  validate       fmt + validate + gitleaks + ansible-lint"
	@echo "  decrypt        sops --decrypt → $(SECRETS_FILE)"
	@echo "  plan           terraform plan -out=$(TFPLAN)"
	@echo "  apply          terraform apply $(TFPLAN)"
	@echo "  inventory      render Ansible inventory from terraform outputs"
	@echo "  wait           wait for cloud-init to finish"
	@echo "  dry-run        ansible-playbook --check --diff"
	@echo "  deploy         ansible-playbook site.yml"
	@echo "  verify         ansible-playbook verify.yml"
	@echo "  clean          shred $(SECRETS_FILE)"
	@echo ""
	@echo "  rollback-xray ROLLBACK_XRAY_VERSION=vX.Y.Z"
	@echo "  rollback-config"
	@echo "  rotate-credentials"
	@echo ""
	@echo "  destroy           Safe terraform destroy (double confirmation)"
	@echo "  backup-state      age-encrypt the local terraform state"
	@echo "  burn-check        External IP reachability probe (check-host.net)"
	@echo "  diff-secrets      Drift detection between deployed config and current secrets"
	@echo "  emit-singbox CLIENT=<name>  Emit full sing-box client JSON"
	@echo "  install-hooks     Install pre-commit hooks for this repo"
	@echo "  molecule-test ROLE=<name>   Run molecule test for one role"
	@echo "  smoke-test        End-to-end traffic test through every enabled profile"
	@echo "  validate-target   Pre-deploy probe of REALITY target (TLS/H2/SAN/uTLS/ASN)"
	@echo "  scan-targets {SEEDS=…|CIDR=…|CRAWL=…}  Discover REALITY targets via RealiTLScanner"
	@echo "  bootstrap-secrets …  Generate full crypto + SOPS-encrypt for a fresh env"
	@echo "  spot-check-secrets   Audit decrypted secrets for placeholders + cert health"
	@echo "  probe-asn HOST=…     One-shot Team Cymru ASN lookup (IP or hostname)"
	@echo "  emit-qr CLIENT=…     PNG QR for the client (TYPE=singbox|uri, OUT=path)"
	@echo "  check-certs          Cert hygiene: SAN, expiry, self-signed, modulus match"
	@echo "  audit-permissions    Local FS audit: age key 0600, no stray plaintext, etc."
	@echo "  asn-drift            Detect ASN drift on the deployed VPS IP, alert via ntfy"
	@echo "  blue-green GREEN_ENV=<name>  Orchestrate blue-green replacement"

check-prereqs:
	@for tool in terraform ansible ansible-playbook ansible-lint sops age gitleaks jq ssh python3; do \
	  command -v $$tool >/dev/null 2>&1 || { echo "missing: $$tool"; exit 1; }; \
	done
	@python3 -c 'import yaml' >/dev/null 2>&1 || { echo "missing: Python module PyYAML"; exit 1; }
	@echo "all prereqs present"

init:
	terraform -chdir=$(TF_ROOT) init

validate:
	terraform -chdir=$(TF_ROOT) fmt -check -recursive
	terraform -chdir=$(TF_ROOT) validate
	gitleaks detect --source . --redact --no-banner
	cd $(ANSIBLE_DIR) && ansible-lint
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/site.yml --syntax-check

decrypt:
	@test -f "$(SOPS_FILE)" || { echo "missing $(SOPS_FILE)"; exit 1; }
	sops --decrypt $(SOPS_FILE) > $(SECRETS_FILE)
	chmod 0600 $(SECRETS_FILE)
	@echo "decrypted to $(SECRETS_FILE)"

plan:
	@test -f "$(TFVARS)" || { echo "missing $(TFVARS) — copy from .example and fill"; exit 1; }
	terraform -chdir=$(TF_ROOT) plan \
	  -var-file=environments/$(ENV).tfvars \
	  -out=$(ENV).tfplan

apply:
	terraform -chdir=$(TF_ROOT) apply $(ENV).tfplan

inventory:
	PROVIDER=$(PROVIDER) ENV=$(ENV) ./scripts/render-inventory.sh

wait:
	PROVIDER=$(PROVIDER) ENV=$(ENV) ./scripts/wait-cloud-init.sh

dry-run:
	@test -f "$(SECRETS_FILE)" || { echo "missing $(SECRETS_FILE) — run 'make decrypt'"; exit 1; }
	VPN_SECRETS_FILE=$(SECRETS_FILE) \
	ansible-playbook $(ANSIBLE_DIR)/playbooks/site.yml --check --diff

deploy:
	@test -f "$(SECRETS_FILE)" || { echo "missing $(SECRETS_FILE) — run 'make decrypt'"; exit 1; }
	VPN_SECRETS_FILE=$(SECRETS_FILE) \
	ansible-playbook $(ANSIBLE_DIR)/playbooks/site.yml

verify:
	VPN_SECRETS_FILE=$(SECRETS_FILE) \
	ansible-playbook $(ANSIBLE_DIR)/playbooks/verify.yml

clean:
	@if [ -f "$(SECRETS_FILE)" ]; then \
	  shred -u $(SECRETS_FILE) 2>/dev/null || rm -f $(SECRETS_FILE); \
	  echo "shredded $(SECRETS_FILE)"; \
	fi

rollback-xray:
	@test -n "$(ROLLBACK_XRAY_VERSION)" || { echo "ROLLBACK_XRAY_VERSION required"; exit 1; }
	VPN_SECRETS_FILE=$(SECRETS_FILE) \
	ROLLBACK_XRAY_VERSION=$(ROLLBACK_XRAY_VERSION) \
	ansible-playbook $(ANSIBLE_DIR)/playbooks/rollback-xray.yml

rollback-config:
	VPN_SECRETS_FILE=$(SECRETS_FILE) \
	ansible-playbook $(ANSIBLE_DIR)/playbooks/rollback-config.yml

rotate-credentials:
	VPN_SECRETS_FILE=$(SECRETS_FILE) \
	ansible-playbook $(ANSIBLE_DIR)/playbooks/rotate-credentials.yml

destroy:
	PROVIDER=$(PROVIDER) ENV=$(ENV) ./scripts/destroy.sh

backup-state:
	PROVIDER=$(PROVIDER) ENV=$(ENV) ./scripts/backup-tf-state.sh

burn-check:
	PROVIDER=$(PROVIDER) ENV=$(ENV) ./scripts/burn-check.sh

diff-secrets:
	@test -f "$(SECRETS_FILE)" || { echo "missing $(SECRETS_FILE) — run 'make decrypt'"; exit 1; }
	PROVIDER=$(PROVIDER) ENV=$(ENV) SECRETS_FILE=$(SECRETS_FILE) ./scripts/diff-secrets.sh

emit-singbox:
	@test -n "$(CLIENT)" || { echo "CLIENT=<name> required"; exit 1; }
	PROVIDER=$(PROVIDER) ENV=$(ENV) ./scripts/emit-singbox.sh $(CLIENT)

install-hooks:
	pip install --user pre-commit
	pre-commit install
	pre-commit install --hook-type commit-msg

molecule-test:
	@test -n "$(ROLE)" || { echo "ROLE=<role-name> required (e.g. baseline, firewall, xray)"; exit 1; }
	cd $(ANSIBLE_DIR)/roles/$(ROLE) && molecule test

smoke-test:
	@test -f "$(SECRETS_FILE)" || { echo "missing $(SECRETS_FILE) — run 'make decrypt'"; exit 1; }
	VPN_SECRETS_FILE=$(SECRETS_FILE) \
	ansible-playbook $(ANSIBLE_DIR)/playbooks/smoke-test.yml

validate-target:
	@test -f "$(SECRETS_FILE)" || { echo "missing $(SECRETS_FILE) — run 'make decrypt'"; exit 1; }
	SOPS_FILE=$(SOPS_FILE) ENV=$(ENV) ./scripts/validate-reality-target.sh

bootstrap-secrets:
	@test -n "$(TARGET)$(SERVER_NAME)" || { \
	  echo "usage: make bootstrap-secrets TARGET=mirror.example.com:443 SERVER_NAME=mirror.example.com"; \
	  echo "  optional: CLIENTS=phone,laptop ENV=prod XHTTP_HOST=vpn.example.com"; \
	  exit 1; }
	./scripts/bootstrap-secrets.sh \
	  $(if $(ENV),--env $(ENV)) \
	  $(if $(CLIENTS),--clients $(CLIENTS)) \
	  --target $(TARGET) --server-name $(SERVER_NAME) \
	  $(if $(XHTTP_HOST),--xhttp-host $(XHTTP_HOST))

spot-check-secrets:
	@test -f "$(SECRETS_FILE)" || { echo "missing $(SECRETS_FILE) — run 'make decrypt'"; exit 1; }
	VPN_SECRETS_FILE=$(SECRETS_FILE) python3 ./scripts/spot-check-secrets.py

probe-asn:
	@test -n "$(HOST)" || { echo "usage: make probe-asn HOST=mirror.example.com"; exit 1; }
	./scripts/probe-asn.sh $(HOST)

emit-qr:
	@test -n "$(CLIENT)" || { echo "usage: make emit-qr CLIENT=phone [TYPE=singbox|uri] [OUT=phone.png]"; exit 1; }
	./scripts/emit-qr.sh $(CLIENT) \
	  $(if $(TYPE),--type $(TYPE)) \
	  $(if $(OUT),--out $(OUT))

check-certs:
	@test -f "$(SECRETS_FILE)" || { echo "missing $(SECRETS_FILE) — run 'make decrypt'"; exit 1; }
	VPN_SECRETS_FILE=$(SECRETS_FILE) ./scripts/check-certs.sh

audit-permissions:
	./scripts/audit-permissions.sh

asn-drift:
	PROVIDER=$(PROVIDER) ENV=$(ENV) ./scripts/asn-drift.sh

scan-targets:
	@test -n "$(SEEDS)$(CIDR)$(CRAWL)" || { \
	  echo "scan-targets needs one of:"; \
	  echo "  make scan-targets SEEDS=path/to/seeds.txt"; \
	  echo "  make scan-targets CIDR=107.172.103.0/24"; \
	  echo "  make scan-targets CRAWL=https://launchpad.net/ubuntu/+archivemirrors"; \
	  exit 1; }
	./scripts/scan-reality-targets.sh \
	  $(if $(SEEDS),--seeds $(SEEDS)) \
	  $(if $(CIDR),--cidr $(CIDR)) \
	  $(if $(CRAWL),--crawl $(CRAWL)) \
	  $(if $(THREADS),--threads $(THREADS)) \
	  $(if $(TIMEOUT),--timeout $(TIMEOUT)) \
	  $(if $(TOP),--top $(TOP)) \
	  $(if $(VALIDATE),--validate)

blue-green:
	@test -n "$(GREEN_ENV)" || { echo "GREEN_ENV=<name> required (e.g. green, spare2)"; exit 1; }
	PROVIDER=$(PROVIDER) BLUE_ENV=$(ENV) GREEN_ENV=$(GREEN_ENV) ./scripts/blue-green.sh
