package validator

import (
	"testing"

	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/structpb"
)

func TestSchemaPayloadPreservesValueProperty(t *testing.T) {
	for _, data := range []map[string]interface{}{
		{"value": 1.0},
		{"value": map[string]interface{}{"nested": true}},
		{"value": "text", "other": true},
	} {
		payload, err := structpb.NewStruct(data)
		require.NoError(t, err)
		expected, err := payload.MarshalJSON()
		require.NoError(t, err)
		actual, err := (&SchemaValidator{}).payloadToJSON(payload)
		require.NoError(t, err)
		require.JSONEq(t, string(expected), string(actual))
	}
}
