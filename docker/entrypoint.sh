#!/bin/sh
set -e

# CLUSTER_PEER_NAME (boxlang.json's modules.boxexpress.settings.cluster.name) has to be a real
# ws://host:port URL another pod can dial directly — ClusterPeer.bx connects to it as-is, see its
# own docblock. POD_IP comes from the Downward API (k8s/deployment.yaml's env), APP_PORT from the
# ConfigMap. Skipped entirely when CLUSTER_PEER_NAME is already set explicitly (e.g. running this
# image outside k8s for local multi-instance testing, matching app.bxs's --port support).
if [ -z "$CLUSTER_PEER_NAME" ] && [ -n "$POD_IP" ]; then
	export CLUSTER_PEER_NAME="ws://${POD_IP}:${APP_PORT:-3000}"
fi

exec boxlang --bx-config ./boxlang.json app.bxs
