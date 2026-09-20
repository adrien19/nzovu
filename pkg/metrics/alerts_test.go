package metrics

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"github.com/prometheus/client_golang/prometheus"

	"github.com/stretchr/testify/require"
	"gopkg.in/yaml.v3"
)

func TestPrometheusAlertsReferenceRegisteredMetrics(t *testing.T) {
	alertBytes, err := os.ReadFile(filepath.Join("..", "..", "monitoring", "prometheus-alerts.yml"))
	require.NoError(t, err)
	var rules struct {
		Groups []struct {
			Rules []struct {
				Alert string `yaml:"alert"`
				Expr  string `yaml:"expr"`
			} `yaml:"rules"`
		} `yaml:"groups"`
	}
	require.NoError(t, yaml.Unmarshal(alertBytes, &rules))

	registered := registeredMetricNames(t)

	metricPattern := regexp.MustCompile(`nzovu_[a-z0-9_]+`)
	for _, group := range rules.Groups {
		for _, rule := range group.Rules {
			for _, metricName := range metricPattern.FindAllString(rule.Expr, -1) {
				baseName := strings.TrimSuffix(metricName, "_bucket")
				_, exists := registered[baseName]
				require.True(t, exists, "alert %s references unregistered metric %s", rule.Alert, metricName)
			}
		}
	}
}

func registeredMetricNames(t *testing.T) map[string]struct{} {
	t.Helper()
	registered := make(map[string]struct{})
	descriptions := make(chan *prometheus.Desc)
	go func() {
		NewMetricsRegistry().registry.Describe(descriptions)
		close(descriptions)
	}()
	pattern := regexp.MustCompile(`fqName: "([^"]+)"`)
	for description := range descriptions {
		match := pattern.FindStringSubmatch(description.String())
		require.Len(t, match, 2)
		registered[match[1]] = struct{}{}
	}
	require.NotEmpty(t, registered)
	for name := range registered {
		require.True(t, strings.HasPrefix(name, "nzovu_"), "unexpected metric namespace: %s", name)
	}
	return registered
}

func TestGrafanaDashboardReferencesRegisteredMetrics(t *testing.T) {
	contents, err := os.ReadFile(filepath.Join("..", "..", "monitoring", "grafana-dashboard.json"))
	require.NoError(t, err)
	var dashboard any
	require.NoError(t, json.Unmarshal(contents, &dashboard))
	registered := registeredMetricNames(t)
	pattern := regexp.MustCompile(`nzovu_[a-z0-9_]+`)
	references := 0
	var visit func(any)
	visit = func(value any) {
		switch value := value.(type) {
		case map[string]any:
			for key, child := range value {
				if expression, ok := child.(string); ok && (key == "expr" || key == "query") {
					for _, metric := range pattern.FindAllString(expression, -1) {
						base := metric
						if _, exists := registered[base]; !exists {
							for _, suffix := range []string{"_bucket", "_sum", "_count"} {
								base = strings.TrimSuffix(base, suffix)
							}
						}
						_, exists := registered[base]
						require.True(t, exists, "dashboard references unregistered metric %s", metric)
						references++
					}
				}
				visit(child)
			}
		case []any:
			for _, child := range value {
				visit(child)
			}
		}
	}
	visit(dashboard)
	require.Positive(t, references)
}

func TestScrapeUsesNzovuMetricNames(t *testing.T) {
	registry := NewMetricsRegistry()
	IncrementMessagesEnqueued("namespace-test")
	recorder := httptest.NewRecorder()
	registry.Handler().ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, "/metrics", nil))
	require.Equal(t, http.StatusOK, recorder.Code)
	require.Contains(t, recorder.Body.String(), `nzovu_messages_enqueued_total{queue_name="namespace-test"}`)
}
