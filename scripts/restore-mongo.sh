#!/usr/bin/env bash
# Restore the gada database from an S3 backup.
#   ./scripts/restore-mongo.sh list    <namespace>
#   ./scripts/restore-mongo.sh restore <namespace> <backup file name>
# Example: ./scripts/restore-mongo.sh restore gada-prod gada-20261120-203001.archive.gz
# The restore REPLACES the current data in the gada database, so it asks you to type the namespace.
set -euo pipefail

BUCKET="${BACKUP_BUCKET:-gada-backups-660880134652}"
cmd="${1:-}"
ns="${2:-}"
[ -n "$cmd" ] && [ -n "$ns" ] || { sed -n 2,6p "$0"; exit 1; }

case "$cmd" in
  list)
    aws s3 ls "s3://${BUCKET}/${ns}/" --region ap-south-1
    ;;
  restore)
    file="${3:?give the backup file name from the list command}"
    read -r -p "This replaces the data in ${ns}. Type the namespace to continue: " answer
    [ "$answer" = "$ns" ] || { echo "Not confirmed, nothing changed."; exit 1; }

    kubectl -n "$ns" delete job gada-mongo-restore --ignore-not-found
    kubectl -n "$ns" apply -f - <<YAML
apiVersion: batch/v1
kind: Job
metadata:
  name: gada-mongo-restore
spec:
  backoffLimit: 0
  activeDeadlineSeconds: 1800
  template:
    spec:
      restartPolicy: Never
      volumes:
        - name: backup
          emptyDir: {}
      initContainers:
        - name: download
          image: amazon/aws-cli:2.17.0
          command: ["sh", "-c"]
          args:
            - aws s3 cp "s3://${BUCKET}/${ns}/${file}" /backup/gada.archive.gz --only-show-errors
          env:
            - name: AWS_DEFAULT_REGION
              value: ap-south-1
          volumeMounts:
            - name: backup
              mountPath: /backup
      containers:
        - name: restore
          image: mongo:7.0
          command: ["sh", "-c"]
          args:
            - mongorestore --uri="\$MONGO_URI" --archive=/backup/gada.archive.gz --gzip --nsInclude='gada.*' --drop
          env:
            - name: MONGO_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: gada-secrets
                  key: mongo-root-password
            - name: MONGO_URI
              value: mongodb://gada_root:\$(MONGO_PASSWORD)@mongo-0.mongo.${ns}.svc.cluster.local:27017/?authSource=admin
          volumeMounts:
            - name: backup
              mountPath: /backup
YAML
    kubectl -n "$ns" wait --for=condition=complete job/gada-mongo-restore --timeout=600s
    kubectl -n "$ns" logs job/gada-mongo-restore -c restore --tail=15
    echo "Restore finished. Check the site, then: kubectl -n ${ns} delete job gada-mongo-restore"
    ;;
  *)
    sed -n 2,6p "$0"; exit 1 ;;
esac
