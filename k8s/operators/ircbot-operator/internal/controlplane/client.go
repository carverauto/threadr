package controlplane

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	cachev1alpha1 "github.com/carverauto/threadr/k8s/operator/ircbot-operator/api/v1alpha1"
)

const (
	defaultSyncInterval = 15 * time.Second
)

type Config struct {
	BaseURL      string
	Token        string
	SyncInterval time.Duration
}

type BotContract struct {
	ID             string                   `json:"id"`
	TenantID       string                   `json:"tenant_id"`
	BotID          string                   `json:"bot_id"`
	Generation     int64                    `json:"generation"`
	Operation      string                   `json:"operation"`
	DeploymentName string                   `json:"deployment_name"`
	Namespace      string                   `json:"namespace"`
	Contract       cachev1alpha1.ThreadrBot `json:"contract"`
}

type ContractClient interface {
	ListBotContracts(ctx context.Context) ([]BotContract, error)
}

type StatusReport struct {
	TenantSubject  string                 `json:"tenantSubject"`
	BotID          string                 `json:"botId"`
	Status         string                 `json:"status"`
	Reason         string                 `json:"reason,omitempty"`
	DeploymentName string                 `json:"deploymentName,omitempty"`
	ObservedAt     time.Time              `json:"observedAt"`
	Generation     int64                  `json:"generation,omitempty"`
	Metadata       map[string]interface{} `json:"metadata,omitempty"`
}

type StatusReporter interface {
	ReportBotStatus(ctx context.Context, report StatusReport) error
}

type HTTPClient struct {
	baseURL    *url.URL
	token      string
	httpClient *http.Client
}

func ConfigFromEnv() (Config, error) {
	syncInterval := defaultSyncInterval

	if raw := strings.TrimSpace(os.Getenv("THREADR_CONTROL_PLANE_SYNC_INTERVAL")); raw != "" {
		parsed, err := time.ParseDuration(raw)
		if err != nil {
			return Config{}, fmt.Errorf("parse THREADR_CONTROL_PLANE_SYNC_INTERVAL: %w", err)
		}

		syncInterval = parsed
	}

	return Config{
		BaseURL:      strings.TrimSpace(os.Getenv("THREADR_CONTROL_PLANE_BASE_URL")),
		Token:        strings.TrimSpace(os.Getenv("THREADR_CONTROL_PLANE_TOKEN")),
		SyncInterval: syncInterval,
	}, nil
}

func (c Config) Enabled() bool {
	return c.BaseURL != "" && c.Token != ""
}

func NewHTTPClient(config Config) (*HTTPClient, error) {
	baseURL, err := url.Parse(config.BaseURL)
	if err != nil {
		return nil, fmt.Errorf("parse control plane base URL: %w", err)
	}

	return &HTTPClient{
		baseURL: baseURL,
		token:   config.Token,
		httpClient: &http.Client{
			Timeout: 15 * time.Second,
		},
	}, nil
}

func (c *HTTPClient) ListBotContracts(ctx context.Context) ([]BotContract, error) {
	endpoint := c.baseURL.ResolveReference(&url.URL{Path: "/api/control-plane/bot-contracts"})
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint.String(), nil)
	if err != nil {
		return nil, fmt.Errorf("build list contracts request: %w", err)
	}

	req.Header.Set("Authorization", "Bearer "+c.token)
	req.Header.Set("Accept", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("request bot contracts: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("request bot contracts: unexpected status %d", resp.StatusCode)
	}

	var payload struct {
		Data []BotContract `json:"data"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		return nil, fmt.Errorf("decode bot contracts response: %w", err)
	}

	return payload.Data, nil
}

func (c *HTTPClient) ReportBotStatus(ctx context.Context, report StatusReport) error {
	body := map[string]interface{}{
		"status": map[string]interface{}{
			"status":          report.Status,
			"reason":          report.Reason,
			"deployment_name": report.DeploymentName,
			"observed_at":     report.ObservedAt.UTC().Format(time.RFC3339),
			"generation":      report.Generation,
			"metadata":        report.Metadata,
		},
	}

	payload, err := json.Marshal(body)
	if err != nil {
		return fmt.Errorf("marshal bot status report: %w", err)
	}

	endpoint := c.baseURL.ResolveReference(&url.URL{
		Path: fmt.Sprintf("/api/control-plane/tenants/%s/bots/%s/status", report.TenantSubject, report.BotID),
	})

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint.String(), bytes.NewReader(payload))
	if err != nil {
		return fmt.Errorf("build bot status report request: %w", err)
	}

	req.Header.Set("Authorization", "Bearer "+c.token)
	req.Header.Set("Accept", "application/json")
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("request bot status report: %w", err)
	}
	defer resp.Body.Close()

	if report.Status == "deleted" && resp.StatusCode == http.StatusNotFound {
		return nil
	}

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("request bot status report: unexpected status %d", resp.StatusCode)
	}

	return nil
}
