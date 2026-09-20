package runtimeenv

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

// Lookup gives an explicitly set Nzovu variable precedence, including an empty value.
func Lookup(key string) (string, bool) {
	if value, exists := os.LookupEnv(key); exists {
		return value, true
	}
	if strings.HasPrefix(key, "NZOVU_") {
		return os.LookupEnv("CHRONOQUEUE_" + strings.TrimPrefix(key, "NZOVU_"))
	}
	return "", false
}

func Get(key string) string {
	value, _ := Lookup(key)
	return value
}

// Bool rejects invalid security settings instead of silently disabling protection.
func Bool(key string, fallback bool) (bool, error) {
	value, exists := Lookup(key)
	_, currentSet := os.LookupEnv(key)
	if !exists || (!currentSet && strings.TrimSpace(value) == "") {
		return fallback, nil
	}
	parsed, err := strconv.ParseBool(strings.TrimSpace(value))
	if err != nil {
		return false, fmt.Errorf("invalid %s: expected true or false", key)
	}
	return parsed, nil
}
