package controller

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/QuantumNous/new-api/common"
	"github.com/QuantumNous/new-api/setting/system_setting"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestGetStatusReturnsEffectiveOIDCDisplayName(t *testing.T) {
	settings := system_setting.GetOIDCSettings()
	originalDisplayName := settings.DisplayName
	originalOptionMap := common.OptionMap
	t.Cleanup(func() {
		settings.DisplayName = originalDisplayName
		common.OptionMap = originalOptionMap
	})
	common.OptionMap = map[string]string{}

	tests := []struct {
		name        string
		displayName string
		want        string
	}{
		{
			name:        "custom name is trimmed",
			displayName: "  Acme SSO  ",
			want:        "Acme SSO",
		},
		{
			name:        "whitespace-only name falls back",
			displayName: "   ",
			want:        "OIDC",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			settings.DisplayName = tt.displayName
			response := httptest.NewRecorder()
			context, _ := gin.CreateTestContext(response)
			context.Request = httptest.NewRequest(http.MethodGet, "/api/status", nil)

			GetStatus(context)

			var payload struct {
				Success bool           `json:"success"`
				Data    map[string]any `json:"data"`
			}
			require.NoError(t, common.Unmarshal(response.Body.Bytes(), &payload))
			require.True(t, payload.Success)
			assert.Equal(t, tt.want, payload.Data["oidc_display_name"])
		})
	}
}

func TestSendEmailVerificationRejectsWhenRegistrationDisabled(t *testing.T) {
	tests := []struct {
		name                    string
		registerEnabled         bool
		passwordRegisterEnabled bool
		wantMessage             string
	}{
		{
			name:            "registration disabled",
			registerEnabled: false, passwordRegisterEnabled: true,
			wantMessage: "New user registration has been disabled by administrator",
		},
		{
			name:            "password registration disabled",
			registerEnabled: true, passwordRegisterEnabled: false,
			wantMessage: "Password registration has been disabled by administrator, please use third-party account verification",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			previousRegister := common.RegisterEnabled
			previousPasswordRegister := common.PasswordRegisterEnabled
			t.Cleanup(func() {
				common.RegisterEnabled = previousRegister
				common.PasswordRegisterEnabled = previousPasswordRegister
			})
			common.RegisterEnabled = tt.registerEnabled
			common.PasswordRegisterEnabled = tt.passwordRegisterEnabled

			response := httptest.NewRecorder()
			context, _ := gin.CreateTestContext(response)
			context.Request = httptest.NewRequest(http.MethodGet, "/api/verification?email=new-user@example.com", nil)

			SendEmailVerification(context)

			var payload struct {
				Success bool   `json:"success"`
				Message string `json:"message"`
			}
			require.NoError(t, common.Unmarshal(response.Body.Bytes(), &payload))
			require.False(t, payload.Success)
			assert.Equal(t, tt.wantMessage, payload.Message)
		})
	}
}
