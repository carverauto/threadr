package controlplane

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestHTTPClientListBotContracts(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/control-plane/bot-contracts" {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}

		if got := r.Header.Get("Authorization"); got != "Bearer test-token" {
			t.Fatalf("unexpected authorization header: %s", got)
		}

		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"data":[{"id":"contract-1","tenant_id":"tenant-1","bot_id":"bot-1","generation":2,"operation":"apply","deployment_name":"threadr-acme-main","namespace":"threadr","contract":{"apiVersion":"cache.threadr.ai/v1alpha1","kind":"ThreadrBot","metadata":{"name":"threadr-acme-main","namespace":"threadr"},"spec":{"controlPlane":{"tenantId":"tenant-1","tenantSubject":"acme","botId":"bot-1","generation":2},"desiredState":"running","platform":"irc","workload":{"deploymentName":"threadr-acme-main","image":"threadr-bot:latest","replicas":1}}}}]}`))
	}))
	defer server.Close()

	client, err := NewHTTPClient(Config{BaseURL: server.URL, Token: "test-token"})
	if err != nil {
		t.Fatalf("new HTTP client: %v", err)
	}

	contracts, err := client.ListBotContracts(context.Background())
	if err != nil {
		t.Fatalf("list bot contracts: %v", err)
	}

	if len(contracts) != 1 {
		t.Fatalf("expected 1 contract, got %d", len(contracts))
	}

	if contracts[0].Generation != 2 {
		t.Fatalf("unexpected generation: %d", contracts[0].Generation)
	}

	if contracts[0].Contract.Spec.ControlPlane.TenantSubject != "acme" {
		t.Fatalf("unexpected tenant subject: %s", contracts[0].Contract.Spec.ControlPlane.TenantSubject)
	}
}

func TestHTTPClientReportBotStatus(t *testing.T) {
	var body map[string]map[string]interface{}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/control-plane/tenants/acme/bots/bot-1/status" {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}

		if r.Method != http.MethodPost {
			t.Fatalf("unexpected method: %s", r.Method)
		}

		if got := r.Header.Get("Authorization"); got != "Bearer test-token" {
			t.Fatalf("unexpected authorization header: %s", got)
		}

		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Fatalf("decode request body: %v", err)
		}

		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"data":{}}`))
	}))
	defer server.Close()

	client, err := NewHTTPClient(Config{BaseURL: server.URL, Token: "test-token"})
	if err != nil {
		t.Fatalf("new HTTP client: %v", err)
	}

	observedAt := time.Date(2026, 3, 5, 12, 0, 0, 0, time.UTC)
	err = client.ReportBotStatus(context.Background(), StatusReport{
		TenantSubject:  "acme",
		BotID:          "bot-1",
		Status:         "running",
		Reason:         "deployment_available",
		DeploymentName: "threadr-acme-main",
		ObservedAt:     observedAt,
		Generation:     2,
		Metadata: map[string]interface{}{
			"ready_replicas":     1,
			"available_replicas": 1,
		},
	})
	if err != nil {
		t.Fatalf("report bot status: %v", err)
	}

	status := body["status"]
	if status["status"] != "running" {
		t.Fatalf("unexpected status: %v", status["status"])
	}

	if status["reason"] != "deployment_available" {
		t.Fatalf("unexpected reason: %v", status["reason"])
	}

	if status["deployment_name"] != "threadr-acme-main" {
		t.Fatalf("unexpected deployment_name: %v", status["deployment_name"])
	}

	if status["generation"] != float64(2) {
		t.Fatalf("unexpected generation: %v", status["generation"])
	}

	if status["observed_at"] != observedAt.Format(time.RFC3339) {
		t.Fatalf("unexpected observed_at: %v", status["observed_at"])
	}
}

func TestHTTPClientReportBotStatusTreatsDeletedNotFoundAsSuccess(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
	}))
	defer server.Close()

	client, err := NewHTTPClient(Config{BaseURL: server.URL, Token: "test-token"})
	if err != nil {
		t.Fatalf("new HTTP client: %v", err)
	}

	err = client.ReportBotStatus(context.Background(), StatusReport{
		TenantSubject: "acme",
		BotID:         "bot-1",
		Status:        "deleted",
		ObservedAt:    time.Now().UTC(),
	})
	if err != nil {
		t.Fatalf("deleted not-found response should be treated as success: %v", err)
	}
}
