{{- define "gada.podTemplate" -}}
metadata:
  annotations:
    checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
  labels:
    app: gada-app
    mongo-client: "true"
spec:
  {{- if .Values.hardening.enabled }}
  automountServiceAccountToken: false
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
  {{- end }}
  # Wait until MongoDB accepts connections, so the app does not crash-loop while mongo-0 is still starting.
  # This pod carries mongo-client: "true", so the network policy already allows this check.
  initContainers:
    - name: wait-for-mongo
      image: busybox:1.36
      command:
        - sh
        - -c
        - until nc -z -w 2 mongo-0.mongo.{{ .Release.Namespace }}.svc.cluster.local 27017; do echo "waiting for mongo"; sleep 2; done
      resources:
        requests:
          cpu: 10m
          memory: 16Mi
        limits:
          memory: 32Mi
      {{- if .Values.hardening.enabled }}
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop: ["ALL"]
      {{- end }}
  containers:
    - name: app
      image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
      ports:
        - containerPort: 3000
        - name: metrics
          containerPort: 9464
      envFrom:
        - configMapRef:
            name: gada-config
      env:
        - name: APP_VERSION
          value: {{ .Values.image.tag | quote }}
        - name: MONGO_PASSWORD
          valueFrom:
            secretKeyRef:
              name: {{ .Values.secretName }}
              key: mongo-root-password
        - name: MONGO_URI
          value: mongodb://gada_root:$(MONGO_PASSWORD)@mongo-0.mongo.{{ .Release.Namespace }}.svc.cluster.local:27017/gada?authSource=admin
        - name: JWT_SECRET
          valueFrom:
            secretKeyRef:
              name: {{ .Values.secretName }}
              key: jwt-secret
        - name: ADMIN_PASSWORD
          valueFrom:
            secretKeyRef:
              name: {{ .Values.secretName }}
              key: admin-password
      startupProbe:
        httpGet:
          path: /health
          port: 3000
        periodSeconds: 3
        timeoutSeconds: 3
        failureThreshold: 20
      readinessProbe:
        httpGet:
          path: /ready
          port: 3000
        periodSeconds: 5
        timeoutSeconds: 3
        failureThreshold: 2
      livenessProbe:
        httpGet:
          path: /health
          port: 3000
        periodSeconds: 10
        timeoutSeconds: 3
        failureThreshold: 3
      resources:
        {{- toYaml .Values.app.resources | nindent 12 }}
      {{- if .Values.hardening.enabled }}
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop: ["ALL"]
      volumeMounts:
        - name: tmp
          mountPath: /tmp
      {{- end }}
  {{- if .Values.hardening.enabled }}
  volumes:
    - name: tmp
      emptyDir: {}
  {{- end }}
{{- end -}}
