package util

import (
	"errors"

	"github.com/sirupsen/logrus"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

var (
	ErrUnknown = errors.New("unknown argument passed")

	ErrInvalidArgument = errors.New("invalid argument passed")
	log                *logrus.Logger //nolint:unused
)

type ErrorLevel int

const (
	ERROR_LEVEL_INFO ErrorLevel = iota
	ERROR_LEVEL_ERROR
	ERROR_LEVEL_DEBUG
)

type NzovuError struct {
	Level   ErrorLevel
	Code    codes.Code // gRPC status code
	Message string
	Err     error
}

func (e *NzovuError) Error() string {
	return e.Err.Error()
}

// Convert the NzovuError to a gRPC status error
func (e *NzovuError) GRPCStatus() error {
	if e.Err != nil {
		return status.Errorf(e.Code, "%s: %s", e.Message, e.Err.Error())
	}
	return status.Errorf(e.Code, "%s", e.Message)
}

func NewNzovuError(level ErrorLevel, code codes.Code, err error, msg string) *NzovuError {
	return &NzovuError{
		Level:   level,
		Code:    code,
		Err:     err,
		Message: msg,
	}
}
