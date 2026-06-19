package service

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/QuantumNous/new-api/common"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func requireCodexWhamRequestHeaders(t *testing.T, r *http.Request) {
	t.Helper()
	require.Equal(t, "Bearer access-token", r.Header.Get("Authorization"))
	require.Equal(t, "account-123", r.Header.Get("chatgpt-account-id"))
	require.Equal(t, "application/json", r.Header.Get("Accept"))
	require.Equal(t, "codex_cli_rs", r.Header.Get("originator"))
}

func TestFetchCodexWhamRateLimitResetCreditsSendsAuthenticatedGet(t *testing.T) {
	called := false
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		called = true
		require.Equal(t, http.MethodGet, r.Method)
		require.Equal(t, "/backend-api/wham/rate-limit-reset-credits", r.URL.Path)
		requireCodexWhamRequestHeaders(t, r)

		w.WriteHeader(http.StatusAccepted)
		_, err := w.Write([]byte(`{"credits":[{"id":"reset-1"}]}`))
		require.NoError(t, err)
	}))
	defer server.Close()

	statusCode, body, err := FetchCodexWhamRateLimitResetCredits(
		context.Background(),
		server.Client(),
		server.URL+"/",
		" access-token ",
		" account-123 ",
	)

	require.NoError(t, err)
	assert.Equal(t, http.StatusAccepted, statusCode)
	assert.JSONEq(t, `{"credits":[{"id":"reset-1"}]}`, string(body))
	assert.True(t, called)
}

func TestConsumeCodexWhamRateLimitResetCreditSendsAuthenticatedPostWithRedeemID(t *testing.T) {
	called := false
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		called = true
		require.Equal(t, http.MethodPost, r.Method)
		require.Equal(t, "/backend-api/wham/rate-limit-reset-credits/consume", r.URL.Path)
		requireCodexWhamRequestHeaders(t, r)
		require.True(t, strings.HasPrefix(r.Header.Get("Content-Type"), "application/json"))

		var payload struct {
			RedeemRequestID string `json:"redeem_request_id"`
		}
		require.NoError(t, common.DecodeJson(r.Body, &payload))
		_, err := uuid.Parse(payload.RedeemRequestID)
		require.NoError(t, err)

		w.WriteHeader(http.StatusCreated)
		_, err = w.Write([]byte(`{"ok":true}`))
		require.NoError(t, err)
	}))
	defer server.Close()

	statusCode, body, err := ConsumeCodexWhamRateLimitResetCredit(
		context.Background(),
		server.Client(),
		server.URL,
		" access-token ",
		" account-123 ",
	)

	require.NoError(t, err)
	assert.Equal(t, http.StatusCreated, statusCode)
	assert.JSONEq(t, `{"ok":true}`, string(body))
	assert.True(t, called)
}
