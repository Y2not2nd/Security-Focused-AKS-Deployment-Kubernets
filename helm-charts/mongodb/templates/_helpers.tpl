{{- define "mongodb.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- .Release.Name -}}
{{- end -}}
{{- end -}}

{{- define "mongodb.labels" -}}
app: mongodb
app.kubernetes.io/name: mongodb
app.kubernetes.io/instance: {{ include "mongodb.fullname" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
