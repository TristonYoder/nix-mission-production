#!/usr/bin/env bash
# One-time setup for automatic enrollment (.github/workflows/enroll-host.yml).
# Run on the deploy Mac, from a clean tree, with `gh` signed in as the repo
# owner and the agenix admin key at ~/.ssh/agenix (or $AGENIX_IDENTITY):
#
#   macos-firstboot/setup-enrollment.sh
#
# 1. Makes a CI agenix key: public half -> secrets/ci-key.pub (a recipient of
#    every secret), private half -> the "rekey" environment's AGENIX_CI_KEY
#    secret on GitHub, then deleted here.
# 2. Re-keys the secrets with your admin key and commits (not pushed).
# 3. Creates the "rekey" environment (main only) and lets Actions open PRs.
#
# The issue-only token for the package is made by hand; this prints how.
# Revoke CI later: delete secrets/ci-key.pub, re-key, and delete the secret.
set -euo pipefail
cd "$(dirname "$0")/.."

AGENIX_IDENTITY=${AGENIX_IDENTITY:-$HOME/.ssh/agenix}
die() { echo "error: $*" >&2; exit 1; }
step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

[ -z "$(git status --porcelain)" ] || die "working tree has uncommitted changes; commit first"
[ -f "$AGENIX_IDENTITY" ] || die "need the agenix admin key at $AGENIX_IDENTITY"
gh auth status >/dev/null 2>&1 || die "gh is not signed in (gh auth login)"
repo=$(nix eval --raw .#inventory.generic.repo)

if [ -f secrets/ci-key.pub ]; then
  echo "secrets/ci-key.pub exists already; skipping key creation"
else
  step "Create CI agenix key"
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  ssh-keygen -q -t ed25519 -N '' -C agenix-ci -f "$tmp/ci"
  awk '{print $1, $2}' "$tmp/ci.pub" > secrets/ci-key.pub

  step "Store the private half in GitHub (environment: rekey)"
  gh api -X PUT "repos/$repo/environments/rekey" --input - >/dev/null <<'EOF'
{"deployment_branch_policy": {"protected_branches": false, "custom_branch_policies": true}}
EOF
  gh api -X POST "repos/$repo/environments/rekey/deployment-branch-policies" \
    -f name=main -f type=branch >/dev/null 2>&1 || true # exists already
  gh secret set AGENIX_CI_KEY --env rekey --repo "$repo" < "$tmp/ci"
  rm -P "$tmp/ci" 2>/dev/null || rm -f "$tmp/ci"

  step "Re-key secrets for the CI key"
  (cd secrets && nix develop .. -c agenix -r -i "$AGENIX_IDENTITY")
  git add secrets
  git commit -q -m "secrets: add CI re-key recipient for host enrollment"
  echo "committed (not pushed)"
fi

step "Let GitHub Actions open pull requests"
gh api -X PUT "repos/$repo/actions/permissions/workflow" \
  -f default_workflow_permissions=read -F can_approve_pull_request_reviews=true

cat <<EOF

Done. Remaining:
  - git push
  - Make the enrollment token: github.com > Settings > Developer settings >
    Fine-grained tokens > Generate new token
      Resource owner: the owner of $repo
      Repository access: Only select repositories > $repo
      Permissions: Issues: Read and write (nothing else)
      Expiration: your choice; rebuild the package when it expires
    Save it to a file kept with the install USB (not in this repo), then:
      macos-firstboot/build.sh --token-file /path/to/token
  - If the token belongs to an account other than the repo owner:
      gh variable set ENROLL_ISSUE_AUTHOR --repo $repo --body <that-login>
EOF
