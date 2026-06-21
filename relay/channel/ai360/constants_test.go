package ai360

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestModelListContainsAdvertisedModels(t *testing.T) {
	require.NotEmpty(t, ModelList)

	assert.Contains(t, ModelList, "360gpt-turbo")
	assert.Contains(t, ModelList, "360GPT_S2_V9")
	assert.Contains(t, ModelList, "embedding-bert-512-v1")
}
