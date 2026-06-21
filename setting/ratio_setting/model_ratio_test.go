package ratio_setting

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestDefaultModelRatiosKeepAdvertisedLegacyAndAi360Models(t *testing.T) {
	ratios := GetDefaultModelRatioMap()
	require.NotEmpty(t, ratios)

	assert.Equal(t, 1.0, ratios["davinci-002"])
	assert.Equal(t, 0.2, ratios["babbage-002"])
	assert.Equal(t, 10.0, ratios["davinci"])
	assert.Equal(t, 10.0, ratios["curie"])
	assert.Equal(t, 10.0, ratios["babbage"])
	assert.Equal(t, 10.0, ratios["ada"])
	assert.Equal(t, 0.0858, ratios["360gpt-turbo"])
	assert.Equal(t, 0.8572, ratios["360gpt-pro"])
	assert.Equal(t, 0.0715, ratios["embedding-bert-512-v1"])
}
