{{- define "app.name" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- define "app.selector" -}}
app.kubernetes.io/name: multicloud-app
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
{{- define "app.labels" -}}
{{ include "app.selector" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: "{{ .Chart.Name }}-{{ .Chart.Version }}"
{{- end -}}
{{- define "app.image" -}}
{{- if .Values.image.digest -}}
{{ .Values.image.repository }}@{{ .Values.image.digest }}
{{- else -}}
{{ .Values.image.repository }}:{{ .Values.image.tag }}
{{- end -}}
{{- end -}}
