package operation

import (
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
	"collect_metrics": {},
	"sync_files":      {},
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
	ExpectedRevision string                 `json:"expected_revision,omitempty"`
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

func (s *State) HasResult(targetKey string) bool {
	for _, result := range s.TargetResults {
		if result.TargetKey == targetKey {
			return true
		}
	}
	return false
}
