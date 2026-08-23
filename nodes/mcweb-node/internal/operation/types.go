package operation

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"time"
)

const (
	ProtocolVersion       = 2
	PhaseDispatched       = "dispatched"
	PhaseRunning          = "running"
	PhaseResultPendingAck = "result_pending_ack"
)

var supportedOperationTypes = map[string]struct{}{
	"collect_metrics":       {},
	"sync_files":            {},
	"world_backup_create":   {},
	"world_restore_execute": {},
}

type Batch struct {
	ProtocolVersion int                    `json:"protocol_version"`
	ID              string                 `json:"id"`
	OperationID     string                 `json:"operation_id"`
	DeliveryID      string                 `json:"delivery_id"`
	OperationType   string                 `json:"operation_type"`
	PayloadDigest   string                 `json:"payload_digest"`
	SharedPayload   map[string]interface{} `json:"shared_payload"`
	Targets         []Target               `json:"targets"`
}

type Target struct {
	TargetKey        string                 `json:"target_key"`
	ServerID         string                 `json:"server_id"`
	TaskType         string                 `json:"task_type"`
	ExpectedRevision *string                `json:"expected_revision"`
	Payload          map[string]interface{} `json:"payload"`
}

type TargetResult struct {
	TargetKey       string                 `json:"target_key"`
	Status          string                 `json:"status"`
	AppliedRevision string                 `json:"applied_revision,omitempty"`
	Result          map[string]interface{} `json:"result"`
	ErrorCode       string                 `json:"error_code,omitempty"`
	ErrorMessage    string                 `json:"error_message,omitempty"`
	StartedAt       time.Time              `json:"started_at"`
	CompletedAt     time.Time              `json:"completed_at"`
}

type State struct {
	Batch             Batch          `json:"batch"`
	Phase             string         `json:"phase"`
	TargetResults     []TargetResult `json:"target_results"`
	AcknowledgementID string         `json:"acknowledgement_id,omitempty"`
	UpdatedAt         time.Time      `json:"updated_at"`
}

func (b Batch) Validate() error {
	if b.ProtocolVersion != ProtocolVersion {
		return fmt.Errorf("unsupported operation protocol version: %d", b.ProtocolVersion)
	}
	if b.ID == "" || b.OperationID == "" || b.DeliveryID == "" || b.PayloadDigest == "" {
		return fmt.Errorf("operation batch identifiers are incomplete")
	}
	if _, ok := supportedOperationTypes[b.OperationType]; !ok {
		return fmt.Errorf("unsupported operation type: %s", b.OperationType)
	}
	if len(b.Targets) == 0 {
		return fmt.Errorf("operation batch has no targets")
	}
	if len(b.PayloadDigest) != sha256.Size*2 {
		return fmt.Errorf("operation payload digest is invalid")
	}
	if _, err := hex.DecodeString(b.PayloadDigest); err != nil {
		return fmt.Errorf("operation payload digest is invalid")
	}
	expectedDigest, err := b.canonicalPayloadDigest()
	if err != nil || expectedDigest != b.PayloadDigest {
		return fmt.Errorf("operation payload digest mismatch")
	}
	if (b.OperationType == "world_backup_create" || b.OperationType == "world_restore_execute") && len(b.Targets) != 1 {
		return fmt.Errorf("managed world operation requires exactly one target")
	}

	seen := make(map[string]struct{}, len(b.Targets))
	for _, target := range b.Targets {
		if target.TargetKey == "" || target.ServerID == "" {
			return fmt.Errorf("operation target identifiers are incomplete")
		}
		if target.TaskType != b.OperationType {
			return fmt.Errorf("operation target %s has mismatched task type", target.TargetKey)
		}
		if _, exists := seen[target.TargetKey]; exists {
			return fmt.Errorf("duplicate operation target: %s", target.TargetKey)
		}
		seen[target.TargetKey] = struct{}{}
	}
	return nil
}

func (b Batch) canonicalPayloadDigest() (string, error) {
	targets := make([]map[string]interface{}, 0, len(b.Targets))
	for _, target := range b.Targets {
		targets = append(targets, map[string]interface{}{
			"target_key":        target.TargetKey,
			"server_id":         target.ServerID,
			"task_type":         target.TaskType,
			"expected_revision": target.ExpectedRevision,
			"payload":           target.Payload,
		})
	}
	payload := map[string]interface{}{
		"protocol_version": b.ProtocolVersion,
		"operation_id":     b.OperationID,
		"operation_type":   b.OperationType,
		"shared_payload":   b.SharedPayload,
		"targets":          targets,
	}
	encoded, err := railsCanonicalJSON(payload)
	if err != nil {
		return "", err
	}
	digest := sha256.Sum256(encoded)
	return hex.EncodeToString(digest[:]), nil
}

func railsCanonicalJSON(value interface{}) ([]byte, error) {
	var buffer bytes.Buffer
	encoder := json.NewEncoder(&buffer)
	encoder.SetEscapeHTML(false)
	if err := encoder.Encode(value); err != nil {
		return nil, err
	}
	encoded := bytes.TrimSuffix(buffer.Bytes(), []byte{'\n'})
	encoded = bytes.ReplaceAll(encoded, []byte(`\u2028`), []byte("\u2028"))
	encoded = bytes.ReplaceAll(encoded, []byte(`\u2029`), []byte("\u2029"))
	return encoded, nil
}

func (s *State) HasResult(targetKey string) bool {
	for _, result := range s.TargetResults {
		if result.TargetKey == targetKey {
			return true
		}
	}
	return false
}
