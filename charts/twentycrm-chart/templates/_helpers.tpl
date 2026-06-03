{{/*
Expand the name of the chart.
*/}}
{{- define "twentycrm-chart.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "twentycrm-chart.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Namespace (allows override, mirrors common chart conventions).
*/}}
{{- define "twentycrm-chart.namespace" -}}
{{- default .Release.Namespace .Values.namespaceOverride }}
{{- end }}

{{/*
Chart label (name + version).
*/}}
{{- define "twentycrm-chart.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels (includes user-supplied commonLabels).
*/}}
{{- define "twentycrm-chart.labels" -}}
helm.sh/chart: {{ include "twentycrm-chart.chart" . }}
{{ include "twentycrm-chart.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: twenty
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "twentycrm-chart.selectorLabels" -}}
app.kubernetes.io/name: {{ include "twentycrm-chart.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Common annotations (applied to every object's metadata).
*/}}
{{- define "twentycrm-chart.annotations" -}}
{{- with .Values.commonAnnotations }}
{{- toYaml . }}
{{- end }}
{{- end }}

{{/*
Component resource names.
*/}}
{{- define "twentycrm-chart.serverName" -}}{{ include "twentycrm-chart.fullname" . }}-server{{- end }}
{{- define "twentycrm-chart.workerName" -}}{{ include "twentycrm-chart.fullname" . }}-worker{{- end }}
{{- define "twentycrm-chart.dbName" -}}{{ include "twentycrm-chart.fullname" . }}-db{{- end }}
{{- define "twentycrm-chart.redisName" -}}{{ include "twentycrm-chart.fullname" . }}-redis{{- end }}
{{- define "twentycrm-chart.configMapName" -}}{{ include "twentycrm-chart.fullname" . }}-config{{- end }}

{{/*
Fully-qualified, in-cluster service hostnames.
*/}}
{{- define "twentycrm-chart.serverHost" -}}
{{- printf "%s.%s.svc.%s" (include "twentycrm-chart.serverName" .) (include "twentycrm-chart.namespace" .) .Values.clusterDomain -}}
{{- end }}
{{- define "twentycrm-chart.dbHost" -}}
{{- if .Values.postgresql.host }}{{ .Values.postgresql.host }}{{- else }}{{ printf "%s.%s.svc.%s" (include "twentycrm-chart.dbName" .) (include "twentycrm-chart.namespace" .) .Values.clusterDomain }}{{- end }}
{{- end }}
{{- define "twentycrm-chart.redisHost" -}}
{{- printf "%s.%s.svc.%s" (include "twentycrm-chart.redisName" .) (include "twentycrm-chart.namespace" .) .Values.clusterDomain -}}
{{- end }}

{{/*
Name of the generated Secret this chart creates from values.
*/}}
{{- define "twentycrm-chart.generatedSecretName" -}}
{{- include "twentycrm-chart.fullname" . }}-secret
{{- end }}

{{/*
Secret that holds the server/worker sensitive env (APP_SECRET, ENCRYPTION_KEY,
FALLBACK_ENCRYPTION_KEY, PG_DATABASE_URL): the user-supplied secret.secretRef, or
the generated Secret.
*/}}
{{- define "twentycrm-chart.mainSecretName" -}}
{{- if .Values.secret.secretRef }}{{ tpl .Values.secret.secretRef . }}{{- else }}{{ include "twentycrm-chart.generatedSecretName" . }}{{- end }}
{{- end }}

{{/*
Secret that holds the PostgreSQL password: postgresql.auth.secretRef, or the
generated Secret.
*/}}
{{- define "twentycrm-chart.dbSecretName" -}}
{{- if .Values.postgresql.auth.secretRef }}{{ tpl .Values.postgresql.auth.secretRef . }}{{- else }}{{ include "twentycrm-chart.generatedSecretName" . }}{{- end }}
{{- end }}

{{/*
Whether the chart needs to generate a Secret from values (i.e. some sensitive
value is NOT sourced from a pre-existing secretRef).
Returns "true" or "".
*/}}
{{- define "twentycrm-chart.generatesSecret" -}}
{{- if or (not .Values.secret.secretRef) (and .Values.postgresql.enabled (not .Values.postgresql.auth.secretRef)) (.Values.secret.extraEnv) -}}
true
{{- end }}
{{- end }}

{{/*
Sensitive env for the server & worker. Iterates the OPEN map secret.secretRefKey
(<ENV_VAR>: <key-in-secret>) and renders one secretKeyRef per entry, sourced from
mainSecretName. Also injects secret.extraEnv (env var name -> generated key).
No hardcoded env-var list.
*/}}
{{- define "twentycrm-chart.serverSecretEnv" -}}
{{- $name := include "twentycrm-chart.mainSecretName" . -}}
{{- range $envVar, $key := .Values.secret.secretRefKey }}
- name: {{ $envVar }}
  valueFrom:
    secretKeyRef:
      name: {{ $name }}
      key: {{ $key }}
{{- end }}
{{- range $envVar, $_ := .Values.secret.extraEnv }}
- name: {{ $envVar }}
  valueFrom:
    secretKeyRef:
      name: {{ include "twentycrm-chart.generatedSecretName" $ }}
      key: {{ $envVar }}
{{- end }}
{{- end }}

{{/*
Sensitive env for the db pod. Iterates the OPEN map postgresql.auth.secretRefKey
(<ENV_VAR>: <key-in-secret>) sourced from dbSecretName.
*/}}
{{- define "twentycrm-chart.dbSecretEnv" -}}
{{- $name := include "twentycrm-chart.dbSecretName" . -}}
{{- range $envVar, $key := .Values.postgresql.auth.secretRefKey }}
- name: {{ $envVar }}
  valueFrom:
    secretKeyRef:
      name: {{ $name }}
      key: {{ $key }}
{{- end }}
{{- end }}

{{/*
Service account name.
*/}}
{{- define "twentycrm-chart.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "twentycrm-chart.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Render a fully-qualified image reference, honouring global.imageRegistry.
Usage: include "twentycrm-chart.imageRef" (dict "image" .Values.image "tag" $tag "global" .Values.global)
*/}}
{{- define "twentycrm-chart.imageRef" -}}
{{- $registry := .image.registry | default .global.imageRegistry -}}
{{- $ref := printf "%s:%s" .image.repository .tag -}}
{{- if $registry }}{{ printf "%s/%s" $registry $ref }}{{ else }}{{ $ref }}{{ end -}}
{{- end }}

{{/*
Server / worker image (image.tag falls back to .Chart.AppVersion).
*/}}
{{- define "twentycrm-chart.image" -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- include "twentycrm-chart.imageRef" (dict "image" .Values.image "tag" $tag "global" .Values.global) -}}
{{- end }}

{{/*
Merged image pull secrets (global + chart-level).
*/}}
{{- define "twentycrm-chart.imagePullSecrets" -}}
{{- $secrets := concat (.Values.global.imagePullSecrets | default list) (.Values.imagePullSecrets | default list) | uniq -}}
{{- with $secrets }}
imagePullSecrets:
{{- toYaml . | nindent 0 }}
{{- end }}
{{- end }}

{{/*
Resolve a storageClass: per-component value, else global.storageClass.
Usage: include "twentycrm-chart.storageClass" (dict "value" .Values.x.persistence.storageClass "global" .Values.global)
*/}}
{{- define "twentycrm-chart.storageClass" -}}
{{- $sc := .value | default .global.storageClass -}}
{{- if $sc }}
storageClassName: {{ $sc | quote }}
{{- end }}
{{- end }}

{{/*
PG_DATABASE_URL - assembled from postgresql.* (mirrors the compose interpolation
postgres://USER:PASSWORD@HOST:PORT/DATABASE), or taken from externalDatabase.url.
Sensitive: lives in the Secret.
*/}}
{{- define "twentycrm-chart.databaseUrl" -}}
{{- if .Values.externalDatabase.url }}
{{- .Values.externalDatabase.url }}
{{- else if .Values.postgresql.auth.secretRef }}
{{- fail "postgresql.auth.secretRef is set, so the chart cannot read the password to assemble PG_DATABASE_URL. Provide the full URL yourself via secret.secretRef (the pgDatabaseUrl key) or externalDatabase.url." }}
{{- else }}
{{- printf "postgres://%s:%s@%s:%v/%s" .Values.postgresql.auth.username .Values.postgresql.auth.password (include "twentycrm-chart.dbHost" .) (.Values.postgresql.port | int) .Values.postgresql.auth.database }}
{{- end }}
{{- end }}

{{/*
REDIS_URL - default redis://<release>-redis:6379 (mirrors the compose default),
or externalRedis.url when set.
*/}}
{{- define "twentycrm-chart.redisUrl" -}}
{{- if .Values.externalRedis.url }}
{{- .Values.externalRedis.url }}
{{- else }}
{{- printf "redis://%s:%v" (include "twentycrm-chart.redisHost" .) (.Values.redis.service.port | int) }}
{{- end }}
{{- end }}

{{/*
APP_SECRET - explicit value, else reuse the value already stored in the
generated Secret (upgrade-stable), else generate a random one. This makes a
default `helm install` work out of the box (like `docker compose up`).
*/}}
{{- define "twentycrm-chart.appSecret" -}}
{{- if .Values.secret.appSecret }}
{{- .Values.secret.appSecret }}
{{- else }}
{{- $key := index .Values.secret.secretRefKey "APP_SECRET" | default "app_secret" }}
{{- $existing := lookup "v1" "Secret" (include "twentycrm-chart.namespace" .) (include "twentycrm-chart.generatedSecretName" .) }}
{{- if and $existing (index ($existing.data | default dict) $key) }}
{{- index $existing.data $key | b64dec }}
{{- else }}
{{- randAlphaNum 32 }}
{{- end }}
{{- end }}
{{- end }}

{{/*
ENCRYPTION_KEY - same generate-and-persist behaviour as appSecret.
*/}}
{{- define "twentycrm-chart.encryptionKey" -}}
{{- if .Values.secret.encryptionKey }}
{{- .Values.secret.encryptionKey }}
{{- else }}
{{- $key := index .Values.secret.secretRefKey "ENCRYPTION_KEY" | default "encryption_key" }}
{{- $existing := lookup "v1" "Secret" (include "twentycrm-chart.namespace" .) (include "twentycrm-chart.generatedSecretName" .) }}
{{- if and $existing (index ($existing.data | default dict) $key) }}
{{- index $existing.data $key | b64dec }}
{{- else }}
{{- randAlphaNum 32 }}
{{- end }}
{{- end }}
{{- end }}
