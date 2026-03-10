// This file is licensed under the terms of the MIT License (see LICENSE file)
// Copyright (c) 2026 Pavel Tsayukov p.tsayukov@gmail.com

package cmdrun

import (
	"errors"
	"flag"
	"fmt"
	"os"
	"sync/atomic"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"
)

func Test_New(t *testing.T) {
	t.Run("default flags", func(t *testing.T) {
		r := New[mockHolder]()

		for _, flagName := range []string{
			"loglevel",
			"verbose",
			"color",
		} {
			assert.NotNil(t, r.flags.set.Lookup(flagName),
				"expected "+flagName+" flag to be set")
		}
	})

	t.Run("nil validator is replaced with no-op", func(t *testing.T) {
		r := New[mockHolder]()

		require.NotNil(t, r.flags.validator)
		require.NoError(t, r.flags.validator(&r.flags.set, &mockHolder{}))
	})

	t.Run("panic if default flags are set by client", func(t *testing.T) {
		require.Panics(t, func() {
			New[mockHolder](WithFlags(
				func(set *flag.FlagSet) (mockHolder, ValidateFlagsFn[mockHolder]) {
					holder := mockHolder{
						key: set.String("loglevel", "info", ""),
					}
					return holder, nil
				}),
			)
		})
	})
}

func Test_WithFlagSet(t *testing.T) {
	t.Run("empty flag set name", func(t *testing.T) {
		r := New[mockHolder]()
		assert.Empty(t, r.flags.set.Name())
	})

	t.Run("custom flag set name", func(t *testing.T) {
		const name = "program"
		r := New[mockHolder](WithFlagSet(name, flag.ExitOnError))

		// No direct way to check flag.ErrorHandling, but we assume that
		// flag.FlagSet.Init works.
		assert.Equal(t, name, r.flags.set.Name())
	})
}

func Test_WithUsage(t *testing.T) {
	visited := false
	usage := func(set *flag.FlagSet) {
		visited = true
	}

	r := New[mockHolder](WithUsage(usage))

	r.flags.set.Usage()
	require.Truef(t, visited, "expected Usage function to be called")
}

func Test_WithFlags(t *testing.T) {
	const (
		commandName    = "program"
		defaultKeyFlag = "X"
		defaultNumFlag = 42
	)

	defineFlags := func(set *flag.FlagSet) (mockHolder, ValidateFlagsFn[mockHolder]) {
		return mockHolder{
				key: set.String("key", defaultKeyFlag, "a test key"),
				num: set.Int("num", defaultNumFlag, "a test number"),
			}, func(set *flag.FlagSet, holder *mockHolder) error {
				if *holder.key == "" {
					return errors.New("key cannot be empty")
				}
				if *holder.num == 0 {
					return errors.New("num cannot be zero")
				}
				return nil
			}
	}

	tests := []struct {
		Name       string
		Args       []string
		Options    []Option
		Run        RunFn[mockHolder]
		WantErrStr string
	}{
		{
			Name: "default flags",
			Run: func(_ *zap.Logger, holder *mockHolder) error {
				if *holder.key != defaultKeyFlag {
					return fmt.Errorf("expected defaut key="+defaultKeyFlag+", got %s",
						*holder.key)
				}
				if *holder.num != defaultNumFlag {
					return fmt.Errorf("expected default num=%d, got %d",
						defaultNumFlag, *holder.num)
				}
				return nil
			},
		},
		{
			Name: "valid flags",
			Args: []string{"--key", "A", "--num", "100"},
			Run: func(_ *zap.Logger, holder *mockHolder) error {
				if *holder.key != "A" {
					return fmt.Errorf("expected key=A, got %s", *holder.key)
				}
				if *holder.num != 100 {
					return fmt.Errorf("expected num=100, got %d", *holder.num)
				}
				return nil
			},
		},
		{
			Name:       "invalid flag",
			Args:       []string{"-="},
			Options:    []Option{WithFlagSet(commandName, flag.ContinueOnError)},
			WantErrStr: "bad flag syntax",
		},
		{
			Name:       "invalid key flag",
			Args:       []string{"--key", "", "--num", "0"},
			WantErrStr: "key cannot be empty",
		},
		{
			Name:       "invalid num flag",
			Args:       []string{"--key", "A", "--num", "0"},
			WantErrStr: "num cannot be zero",
		},
	}

	for _, tt := range tests {
		t.Run(tt.Name, func(t *testing.T) {
			tt.Options = append(tt.Options, WithFlags(defineFlags))
			r := New[mockHolder](tt.Options...)

			if len(tt.Args) == 0 {
				os.Args = []string{os.Args[0]}
			}

			if tt.Run != nil {
				tt.Run = func(_ *zap.Logger, holder *mockHolder) error { return nil }
			}

			err := r.Run(tt.Run, tt.Args...)
			if tt.WantErrStr != "" {
				require.ErrorContains(t, err, tt.WantErrStr)
			} else {
				require.NoError(t, err)
			}
		})
	}
}

func Test_Runner_WithLoggerOptions(t *testing.T) {
	t.Cleanup(func() { mockZapCoreCheck.Store(false) })

	r := New[mockHolder](WithLoggerOptions(zap.WrapCore(
		func(_ zapcore.Core) zapcore.Core {
			return zapcore.NewCore(
				zapcore.NewJSONEncoder(zapcore.EncoderConfig{}),
				&mockWriter{},
				zap.NewAtomicLevelAt(zapcore.InfoLevel),
			)
		},
	)))

	os.Args = []string{os.Args[0]}
	_ = r.Run(func(logger *zap.Logger, _ *mockHolder) error {
		logger.Info("")
		return nil
	})
	require.True(t, mockZapCoreCheck.Load())
}

type mockHolder struct {
	key *string
	num *int
}

type mockWriter struct {
	zapcore.WriteSyncer
}

func (w *mockWriter) Sync() error { return nil }

var mockZapCoreCheck atomic.Bool

func (w *mockWriter) Write([]byte) (int, error) {
	mockZapCoreCheck.Store(true)
	return 0, nil
}
