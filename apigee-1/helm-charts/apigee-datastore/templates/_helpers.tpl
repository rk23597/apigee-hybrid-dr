{{/* vim: set filetype=mustache: */}}

{{/*
  Check the helm binary version to ensure that it meets the minimum version
*/}}
{{- define "helmVersionCheck" -}}
{{- if semverCompare "<v3.10.0" .Capabilities.HelmVersion.Version -}}
{{- fail "Please use at least Helm v3.10.0 or above. You can find more about Helm releases and installation at https://github.com/helm/helm/releases." -}}
{{- end -}}
{{- end -}}

{{/*
  Get cassandra replication factor
*/}}
{{- define "cassandra.rf" -}}
{{- if ge (int .Values.cassandra.replicaCount) 3 -}}
{{- 2 -}}
{{- else -}}
{{- sub (int .Values.cassandra.replicaCount) 1 -}}
{{- end -}}
{{- end -}}

{{/*
  Get cassandra dns service name
*/}}
{{- define "cassandra.svc" -}}
{{- printf "apigee-cassandra-default-%v.apigee-cassandra-default.%s.svc.cluster.local" (include "cassandra.rf" .) .Values.namespace -}}
{{- end -}}

{{/*
    cassandra.storage generates the storage struct which is backward
    compatible to support older "capacity" to "storageSize" transformation.
    @param storage - default storage
*/}}
{{- define "cassandra.storage" -}}
{{- if ($v := get .storage "capacity") -}}
{{- $_ := set .storage "storageSize" $v -}}
{{- $_ := unset .storage "capacity" -}}
{{- end -}}
{{- if ($v := get .storage "storageclass") -}}
{{- $_ := set .storage "storageClass" $v -}}
{{- $_ := unset .storage "storageclass" -}}
{{- end -}}
{{ toYaml .storage }}
{{- end -}}

{{/*
  validateVersion
    @param version - version
*/}}
{{- define "validateVersion" -}}
{{- $v := lower .version | replace "." "" }}
{{- if mustRegexMatch "^[a-z0-9]([a-z0-9-]*[a-z0-9])?$" $v }}
{{- $v -}}
{{- else -}}
{{- fail "version .version is not a valid format" }}
{{- end -}}
{{- end -}}

{{/*
  nodeAffinity.data
*/}}
{{- define "nodeAffinity.data" -}}
nodeAffinity:
  {{- if .requiredForScheduling }}
  requiredDuringSchedulingIgnoredDuringExecution:
    nodeSelectorTerms:
    - matchExpressions:
      - key: {{ quote (index .apigeeData "key") }}
        operator: In
        values:
        - {{ quote (index .apigeeData "value") }}
   {{- end }}
  preferredDuringSchedulingIgnoredDuringExecution:
  - weight: 100
    preference:
      matchExpressions:
      - key: {{ quote (index .apigeeData "key") }}
        operator: In
        values:
        - {{ quote (index .apigeeData "value") }}
{{- end -}}

{{/*
  nodeAffinity.runtime
*/}}
{{- define "nodeAffinity.runtime" -}}
nodeAffinity:
  {{- if .requiredForScheduling }}
  requiredDuringSchedulingIgnoredDuringExecution:
    nodeSelectorTerms:
    - matchExpressions:
      - key: {{ quote (index .apigeeRuntime "key") }}
        operator: In
        values:
        - {{ quote (index .apigeeRuntime "value") }}
  {{- end }}
  preferredDuringSchedulingIgnoredDuringExecution:
  - weight: 100
    preference:
      matchExpressions:
      - key: {{ quote (index .apigeeRuntime "key") }}
        operator: In
        values:
        - {{ quote (index .apigeeRuntime "value") }}
{{- end -}}

{{/*
  http_proxy.url returns the HTTP Proxy URL.
*/}}
{{- define "http_proxy.url" -}}
{{- $auth := "" -}}
{{- if and .Values.httpProxy  -}}
{{- if .Values.httpProxy.username -}}
{{- $auth = default "" ( .Values.httpProxy.username | urlquery ) -}}
{{- if .Values.httpProxy.password -}}
{{- $auth = printf "%s:%s" $auth ( .Values.httpProxy.password | urlquery ) -}}
{{- end -}}
{{- $auth = printf "%s@" $auth -}}
{{- end -}}
{{- if or (eq "http" (lower .Values.httpProxy.scheme)) (eq "https" ( lower .Values.httpProxy.scheme)) -}}
{{- $url := printf "%s://%s%s" (default "http" (lower .Values.httpProxy.scheme | trim)) $auth ( required "httpProxy.host is required" .Values.httpProxy.host) -}}
{{- if .Values.httpProxy.port }}
{{- $url = printf "%s:%d" $url (int .Values.httpProxy.port) -}}
{{- end -}}
{{- $url -}}
{{- else -}}
{{- fail "unsupported scheme for http forward proxy (only HTTP and HTTPS are supported" }}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
  namespace resolves the overridden namespace where a value from --namespace
  flag in the cmd line will have a higher precedence than in the override file
  or the default value from values.yaml.
*/}}
{{- define "namespace" -}}
{{- if eq .Release.Namespace "default" -}}
{{- .Values.namespace -}}
{{- else -}}
{{- .Release.Namespace -}}
{{- end -}}
{{- end -}}

{{/*
  container.image returns the image for the given component
    @param hub - string repo base url
    @param o - object component
    @param n - string image name
*/}}
{{- define "container.image" -}}
{{ if .hub }}
{{- printf "%s/%s:%s" .hub .n .o.image.tag -}}
{{ else }}
{{- printf "%s:%s" .o.image.url .o.image.tag -}}
{{- end -}}
{{- end -}}

{{/*
  tryFileContent.get returns file content otherwise error if file is empty or unreachable
    @param files - .Files object
    @param f - string filepath
*/}}
{{- define "tryFileContent.get" -}}
{{- $tr := (trimPrefix "./" .f) -}}
{{- $c := .files.Get $tr -}}
{{- if empty $c -}}
{{- fail (printf "'%s' is either an empty file or unreachable" $tr) -}}
{{- else -}}
{{- $c -}}
{{- end -}}
{{- end -}}

{{/*
  fwi.enabled will return true if federated workload identity is enabled
  It will also validate the FWI configuration
*/}}
{{- define "fwi.enabled" -}}
    {{- if .Values.gcp.federatedWorkloadIdentity.enabled -}}
        {{- if .Values.gcp.workloadIdentity.enabled -}}
            {{- fail "gcp.workloadIdentity.enabled must be false to use federated workload identity" -}}
        {{- end -}}
        {{- if empty .Values.gcp.federatedWorkloadIdentity.audience -}}
            {{- fail "audience required for federatedWorkloadIdentity" -}}
        {{- end -}}
        {{- if empty .Values.gcp.federatedWorkloadIdentity.credentialSourceFile -}}
            {{- fail "credentialSourceFile required for federatedWorkloadIdentity" -}}
        {{- end -}}
        {{- if or (empty .Values.gcp.federatedWorkloadIdentity.tokenExpiration) (lt (int64 .Values.gcp.federatedWorkloadIdentity.tokenExpiration) 600) -}}
            {{- fail "tokenExpiration >= 600 required for federatedWorkloadIdentity" -}}
        {{- end -}}
        {{- print true -}}
    {{- end -}}
{{- end -}}

{{- define "fwi.tokenPath" -}}
    {{- print (clean (dir .Values.gcp.federatedWorkloadIdentity.credentialSourceFile)) -}}
{{- end -}}

{{- define "fwi.tokenFile" -}}
    {{- print (base .Values.gcp.federatedWorkloadIdentity.credentialSourceFile) -}}
{{- end -}}

{{- define "fwi.tokenFull" -}}
    {{- clean .Values.gcp.federatedWorkloadIdentity.credentialSourceFile -}}
{{- end -}}
