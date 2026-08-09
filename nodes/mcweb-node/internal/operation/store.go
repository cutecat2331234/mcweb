package operation

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

type Store struct {
	path string
}

func NewStore(root string) (*Store, error) {
	if root == "" {
		return nil, fmt.Errorf("operation store root required")
	}
	if err := os.MkdirAll(root, 0o700); err != nil {
		return nil, err
	}
	return &Store{path: filepath.Join(root, "active-operation.json")}, nil
}

func (s *Store) Load() (*State, error) {
	data, err := os.ReadFile(s.path)
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}

	var state State
	if err := json.Unmarshal(data, &state); err != nil {
		return nil, fmt.Errorf("decode active operation: %w", err)
	}
	if err := state.Batch.Validate(); err != nil {
		return nil, err
	}
	return &state, nil
}

func (s *Store) Save(state *State) error {
	if state == nil {
		return fmt.Errorf("operation state required")
	}
	if err := state.Batch.Validate(); err != nil {
		return err
	}
	state.UpdatedAt = time.Now().UTC()

	data, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return err
	}
	tmp := s.path + ".next"
	file, err := os.OpenFile(tmp, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	if _, err = file.Write(data); err == nil {
		err = file.Sync()
	}
	closeErr := file.Close()
	if err != nil {
		_ = os.Remove(tmp)
		return err
	}
	if closeErr != nil {
		_ = os.Remove(tmp)
		return closeErr
	}

	if err := os.Rename(tmp, s.path); err != nil {
		// Windows cannot atomically replace an existing destination with os.Rename.
		// Keep the fully-fsynced next file and replace the old state only at this point.
		if removeErr := os.Remove(s.path); removeErr != nil && !errors.Is(removeErr, os.ErrNotExist) {
			_ = os.Remove(tmp)
			return removeErr
		}
		if retryErr := os.Rename(tmp, s.path); retryErr != nil {
			return retryErr
		}
	}
	return nil
}

func (s *Store) Clear() error {
	err := os.Remove(s.path)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	return err
}
