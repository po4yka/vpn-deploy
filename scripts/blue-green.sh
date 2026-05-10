#!/usr/bin/env bash
# Blue-green replacement orchestrator. Operator-driven (asks for confirmation
# at each pivot point) — automation handles the mechanical parts, the human
# decides when to flip traffic and when to retire the old node.
#
# Required env:
#   BLUE_ENV   the existing live env (e.g. prod)
#   GREEN_ENV  the new env name (e.g. green, prod-2026-05-11)
#   PROVIDER   default: upcloud
#   ANSIBLE_SSH_PRIVATE_KEY_FILE
#
# Optional:
#   GREEN_ZONE  override zone for the green node (default: same as blue)
set -euo pipefail

PROVIDER="${PROVIDER:-upcloud}"
BLUE_ENV="${BLUE_ENV:?BLUE_ENV required}"
GREEN_ENV="${GREEN_ENV:?GREEN_ENV required}"
GREEN_ZONE="${GREEN_ZONE:-}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="${REPO_ROOT}/terraform/providers/${PROVIDER}"
SOPS_FILE="${SOPS_FILE:-${HOME}/.config/vpn-provision/${BLUE_ENV}.secrets.sops.yaml}"
SECRETS_FILE="/tmp/vpn-${BLUE_ENV}.secrets.yaml"

if [[ "${BLUE_ENV}" == "${GREEN_ENV}" ]]; then
  echo "BLUE_ENV and GREEN_ENV must differ" >&2
  exit 1
fi

if [[ -z "${ANSIBLE_SSH_PRIVATE_KEY_FILE:-}" ]]; then
  echo "ANSIBLE_SSH_PRIVATE_KEY_FILE must be set" >&2
  exit 1
fi

step() { echo; echo "==> $*"; }

confirm() {
  local prompt="$1"
  read -r -p "$prompt [yes/NO]: " ans
  [[ "$ans" == "yes" ]]
}

# ---------------------------------------------------------------------------
# 1. Pre-flight: blue must be healthy and we must have its secrets decrypted.
# ---------------------------------------------------------------------------
step "1/8  Verify blue health (BLUE_ENV=${BLUE_ENV})"
if [[ ! -f "$SOPS_FILE" ]]; then
  echo "missing $SOPS_FILE" >&2
  exit 1
fi
sops --decrypt "$SOPS_FILE" > "$SECRETS_FILE"
chmod 0600 "$SECRETS_FILE"
trap 'shred -u "$SECRETS_FILE" 2>/dev/null || rm -f "$SECRETS_FILE"' EXIT

VPN_SECRETS_FILE="$SECRETS_FILE" \
  ENV="${BLUE_ENV}" PROVIDER="${PROVIDER}" \
  make -C "$REPO_ROOT" verify

# ---------------------------------------------------------------------------
# 2. Bootstrap green tfvars from blue (if missing)
# ---------------------------------------------------------------------------
GREEN_TFVARS="${TF_DIR}/environments/${GREEN_ENV}.tfvars"
if [[ ! -f "$GREEN_TFVARS" ]]; then
  step "2/8  Generate green tfvars from blue"
  PROVIDER="$PROVIDER" SOURCE_ENV="$BLUE_ENV" \
    "${REPO_ROOT}/scripts/new-cohort.sh" "$GREEN_ENV" ${GREEN_ZONE:+"$GREEN_ZONE"}
  echo
  echo "Edit $GREEN_TFVARS now if you need to tweak server_name, plan, image, or zone."
  read -r -p "Press Enter when ready, or Ctrl-C to abort: " _
fi

# ---------------------------------------------------------------------------
# 3. Provision green
# ---------------------------------------------------------------------------
step "3/8  Provision green (ENV=${GREEN_ENV})"
ENV="$GREEN_ENV" PROVIDER="$PROVIDER" make -C "$REPO_ROOT" init plan apply

# ---------------------------------------------------------------------------
# 4. Render multi-host inventory and deploy green
# ---------------------------------------------------------------------------
step "4/8  Render multi-host inventory and deploy green"
HOSTS="${PROVIDER}:${BLUE_ENV},${PROVIDER}:${GREEN_ENV}" \
COHORTS="fullstack,fullstack" \
  "${REPO_ROOT}/scripts/render-inventory.sh"

ENV="$GREEN_ENV" PROVIDER="$PROVIDER" make -C "$REPO_ROOT" wait

VPN_SECRETS_FILE="$SECRETS_FILE" \
  ansible-playbook \
    -l "*${GREEN_ENV}*" \
    "${REPO_ROOT}/ansible/playbooks/site.yml"

# ---------------------------------------------------------------------------
# 5. Verify + smoke test green
# ---------------------------------------------------------------------------
step "5/8  Verify + smoke-test green"
VPN_SECRETS_FILE="$SECRETS_FILE" \
  ansible-playbook -l "*${GREEN_ENV}*" "${REPO_ROOT}/ansible/playbooks/verify.yml"

VPN_SECRETS_FILE="$SECRETS_FILE" \
  ansible-playbook -l "*${GREEN_ENV}*" "${REPO_ROOT}/ansible/playbooks/smoke-test.yml"

# ---------------------------------------------------------------------------
# 6. Operator pivot — flip clients / DNS / floating IP
# ---------------------------------------------------------------------------
step "6/8  Operator pivot"
GREEN_IP="$(terraform -chdir="$TF_DIR" output -raw server_ipv4)"
cat <<EOF

Green node is ready. Its public IPv4 is: ${GREEN_IP}

Operator action required:
  - Update DNS for vpn.example.com to point at the green IP, OR
  - Move the floating/reserved IP from blue to green, OR
  - Reissue subscription URLs to clients pointing at green.

Test from a real client (sing-box, NekoBox, husi) via the green path
before continuing. Make sure the urltest selector picks up green.

EOF
if ! confirm "Has traffic been swung to green and verified from a real client?"; then
  echo "Aborting. Green is up; clean up later with: ENV=${GREEN_ENV} make destroy"
  exit 1
fi

# ---------------------------------------------------------------------------
# 7. Drain — keep blue alive
# ---------------------------------------------------------------------------
step "7/8  Drain blue"
echo "Convention: keep blue alive for 24-72 hours so cached client sessions"
echo "fail over to green. Re-run the next step when you're ready to retire blue."
echo
echo "When ready to destroy blue, run:"
echo "    ENV=${BLUE_ENV} make destroy"

# ---------------------------------------------------------------------------
# 8. Promote green to canonical
# ---------------------------------------------------------------------------
step "8/8  (Optional) promote green tfvars to ${BLUE_ENV}"
echo "Once blue is destroyed, you can either:"
echo "  - keep operating under ENV=${GREEN_ENV} (preferred — clean separation)"
echo "  - or rename ${GREEN_ENV}.tfvars to ${BLUE_ENV}.tfvars to keep using ENV=${BLUE_ENV}"
echo
echo "Blue-green orchestration done."
