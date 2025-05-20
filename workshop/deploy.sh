#!/usr/bin/env bash
set -euo pipefail

# 1. Load variables
if [[ ! -f values.env ]]; then
  echo "❌ values.env not found – copy values.env.example → values.env and edit."
  exit 1
fi
export $(grep -v '^#' values.env | xargs)

# 2. Ensure envsubst
if ! command -v envsubst &>/dev/null; then
  echo "⚙️ Installing envsubst..."
  sudo yum install -y gettext
fi

# 3. Apply all resources except Frontend (so Backend LB comes up)
echo "⏳ Deploying Namespace, MongoDB, Backend..."
# split the manifest into two passes: everything before the Frontend Service/Deployment
# here we assume manifests.yaml is ordered as: Namespace→Mongo→Backend→Frontend
# apply up to and including Backend Service:
csplit -sz manifests.yaml '/# Frontend Deployment/' '{*}' >/dev/null
kubectl apply -f xx00  # applies docs before Frontend
rm xx0*                # clean up splits

# 4. Wait for the Backend LB to be healthy
echo "⏳ Waiting for Backend LoadBalancer to get an Ingress..."
LB_HOST=""
until LB_HOST=$(kubectl get svc idurar-backend -n $NAMESPACE \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null) \
      && [[ -n "$LB_HOST" ]]; do
  printf "."; sleep 5
done
echo -e "\n✅ Found LB hostname: $LB_HOST"

# 5. Inject into Frontend Deployment
API_URL="http://$LB_HOST"   # or https:// if you have TLS
echo "🔧 Patching Frontend Deployment with API_URL=$API_URL..."
kubectl set env deployment/idurar-frontend \
  -n "$NAMESPACE" \
  REACT_APP_API_URL="$API_URL"

# 6. Apply the Frontend manifests
echo "🚀 Deploying Frontend Service & Deployment..."
# re-split the manifest to get only the Frontend pieces
csplit -sz manifests.yaml '/# Frontend Deployment/' '{*}' >/dev/null
kubectl apply -f xx01  # this is the chunk starting at "# Frontend Deployment"
rm xx0*

echo "✅ All done! Frontend is configured to hit $API_URL"
echo "   kubectl get all -n $NAMESPACE"