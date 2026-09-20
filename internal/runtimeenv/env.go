package runtimeenv

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

// Lookup preserves the distinction between an unset and explicitly empty variable.
func Lookup(key string) (string, bool) {
	return os.LookupEnv(key)
}

func Get(key string) string {
	value, _ := Lookup(key)
	return value
}

// Bool rejects invalid security settings instead of silently disabling protection.
func Bool(key string, fallback bool) (bool, error) {
	value, exists := Lookup(key)
	if !exists {
		return fallback, nil
	}
	parsed, err := strconv.ParseBool(strings.TrimSpace(value))
	if err != nil {
		return false, fmt.Errorf("invalid %s: expected true or false", key)
	}
	return parsed, nil
}
