# Deploying to DOKS

## Before the first deploy

1. **Managed MySQL** — create a DigitalOcean Managed MySQL database, then apply `db/schema.sql`
   against it directly (`mysql -h <host> -P <port> -u <user> -p < db/schema.sql`). There's no
   migration Job here; schema changes are applied by hand the same way `setup.bxs` documents for
   local dev.
2. **Container registry** — build and push the image (from inside `bxThreads/`):
   ```bash
   docker build -t registry.digitalocean.com/<your-registry>/bxthreads:latest .
   docker push registry.digitalocean.com/<your-registry>/bxthreads:latest
   ```
3. Fill in the placeholders: `deployment.yaml`'s `image:`, `configmap.yaml`'s `DB_HOST`/`SITE_URL`,
   `ingress.yaml`'s `host`, and copy `secret.example.yaml` to `secret.yaml` (gitignored) with real
   values.

## Apply

```bash
kubectl apply -f k8s/configmap.yaml -f k8s/secret.yaml -f k8s/deployment.yaml -f k8s/service.yaml -f k8s/ingress.yaml
```

## Known gap: sessions aren't distributed

`app.bxs` wires up `bxModules.boxexpress.models.middleware.Session` with no `CacheStore` behind
it — sessions are in-memory, per pod. `service.yaml`'s `sessionAffinity: ClientIP` is a stopgap:
it keeps one client pinned to one pod for the affinity window, so a normal browsing session stays
logged in. It does **not** survive a pod restart or a rollout — every session on that pod is just
gone. The real fix is the same pattern `ClusterCache` already uses for cluster peer state: a
JDBCStore-backed session cache (see `README.md`'s "Durable sessions" section in boxlang-express,
and `boxlang.json`'s `caches.clusterPeers` for the shape). Worth doing before this runs with
real user traffic across multiple replicas — not done here because it's a real code change
(`app.bxs`'s `sessionMiddleware.session({...})` call, plus a new `caches` entry and its own
MySQL table), not a manifest.

## Known non-issue: `.cache/img-thumbs`

Mounted as an `emptyDir` per pod deliberately, not shared storage. It's a rebuildable
link-preview thumbnail cache with its own daily prune job (`app.bxs`) — each pod just builds its
own copy independently. Low stakes, not worth a shared volume.

## Cluster peer identity

Each pod's `CLUSTER_PEER_NAME` (`boxlang.json`'s `modules.boxexpress.settings.cluster.name`) is
computed at container start by `docker/entrypoint.sh` from the pod's own IP (via the Downward API
— see `deployment.yaml`'s `env.POD_IP`), since `ClusterPeer.bx` dials that URL directly to relay
STOMP broadcasts and to elect a scheduler leader. Nothing to configure per pod — this is exactly
what makes horizontal scaling (`kubectl scale deployment/bxthreads --replicas=N`) work without
touching any manifest, since cluster membership is TTL/heartbeat-based (`ClusterCache`) rather
than a static peer list.

Check live cluster status against a running pod:
```bash
curl https://bxthreads.example.com/api/cluster -H "X-Api-Key: <API_KEY>"
```
