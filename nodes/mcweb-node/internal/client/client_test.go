package client

import (
	"errors"
	"net/http"
	"testing"
)

func TestIsPermanentHTTPError(t *testing.T) {
	if !IsPermanentHTTPError(&HTTPError{StatusCode: http.StatusNotFound, Body: "missing"}) {
		t.Fatal("expected 404 to be permanent")
	}
	if IsPermanentHTTPError(&HTTPError{StatusCode: http.StatusTooManyRequests, Body: "slow down"}) {
		t.Fatal("expected 429 to be retryable")
	}
	if IsPermanentHTTPError(errors.New("network")) {
		t.Fatal("expected generic error to be retryable")
	}
}
