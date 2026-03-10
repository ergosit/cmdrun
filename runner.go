// This file is licensed under the terms of the MIT License (see LICENSE file)
// Copyright (c) 2026 Pavel Tsayukov p.tsayukov@gmail.com

// Package cmdrun provides the helper wrapper over a command-line program.
package cmdrun

import (
	"flag"
	"fmt"
	"os"

	"github.com/ergosit/cmdlog"
	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"
)

type (
	// Runner is a helper struct for command-line programs.
	Runner[Holder any] struct {
		flags      flags[Holder]
		loggerOpts cmdlog.Options
	}

	flags[Holder any] struct {
		set       flag.FlagSet
		validator ValidateFlagsFn[Holder]
		holder    Holder
	}

	// DefineFlagsFn is intended to set flags via [flag.FlagSet] and returns
	// a new Holder, where pointers to them are meant to be stored, along with
	// [ValidateFlagsFn], if any, or nil:
	//
	// 	type CmdHolder struct{ key *string }
	// 	f := func(*flag.FlagSet) (CmdHolder, ValidateFlagsFn[CmdHolder]) {
	//  	holder := CmdHolder{
	// 			key: set.String("key", "A", "a kind of key"),
	// 		}
	//  	validator := func(set *flag.FlagSet, holder *CmdHolder) error {
	// 			if len(*holder.key) > 1 {
	// 				return errors.New("key must contain one character")
	// 			}
	// 			return nil
	// 		}
	//  	return holder, validator // the latter can be nil
	// 	}
	DefineFlagsFn[Holder any] func(set *flag.FlagSet) (Holder, ValidateFlagsFn[Holder])

	// ValidateFlagsFn is intended to be a validator for flags of [flag.FlagSet].
	ValidateFlagsFn[Holder any] func(set *flag.FlagSet, holder *Holder) error

	// UsageFn is intended to set the [flag.FlagSet] behavior when [flag.FlagSet.Usage] is called.
	UsageFn func(set *flag.FlagSet)

	// RunFn is intended to run the command-line program itself.
	RunFn[Holder any] func(logger *zap.Logger, holder *Holder) error
)

type (
	Option func(r runnerInitializer)

	runnerInitializer interface {
		withFlagSet(name string, errorHandling flag.ErrorHandling)
		withUsage(f UsageFn)
		withFlags(f func(set *flag.FlagSet))
		withLoggerOptions(options ...zap.Option)
	}
)

// New creates a new [Runner] with optional [Option]'s.
//
// It defines a new [flag.FlagSet] with default options:
//   - "loglevel" to set the logging level (default: the Info level);
//   - "verbose" (or "v") for verbose output (the logging level will be overwritten
//     to the Debug level);
//   - "color" for colorful output (default: depends on your terminal).
//
// Options:
//   - [WithFlagSet], otherwise, the default [flag.FlagSet] uses an empty name
//     and the [flag.ContinueOnError] error handling policy according to [flag.FlagSet.Init];
//   - [WithUsage], otherwise, the [flag.FlagSet] uses [flag.DefaultUsage];
//   - [WithFlags], otherwise, no additional flags other than the default ones will be set;
//   - [WithLoggerOptions].
func New[Holder any](options ...Option) *Runner[Holder] {
	r := &Runner[Holder]{
		loggerOpts: cmdlog.NewOptions(zap.NewAtomicLevelAt(zapcore.InfoLevel)),
	}

	for _, o := range options {
		o(r)
	}

	if r.flags.validator == nil {
		r.flags.validator = func(*flag.FlagSet, *Holder) error { return nil }
	}

	// If a client defines their own flags with the same names, the program will
	// panic at the very start.
	r.loggerOpts.LogLevelFlag(&r.flags.set)
	r.loggerOpts.VerboseFlag(&r.flags.set)
	r.loggerOpts.ColorFlag(&r.flags.set)

	return r
}

// WithFlagSet is an [Option] that initializes [flag.FlagSet] with the given name
// and error handling policy.
func WithFlagSet(
	name string,
	errorHandling flag.ErrorHandling,
) Option {
	return func(r runnerInitializer) {
		r.withFlagSet(name, errorHandling)
	}
}

func (r *Runner[Holder]) withFlagSet(
	name string,
	errorHandling flag.ErrorHandling,
) {
	r.flags.set.Init(name, errorHandling)
}

// WithUsage is an [Option] that sets [flag.FlagSet.Usage].
func WithUsage(f UsageFn) Option {
	return func(r runnerInitializer) {
		r.withUsage(f)
	}
}

func (r *Runner[Holder]) withUsage(f UsageFn) {
	r.flags.set.Usage = func() { f(&r.flags.set) }
}

// WithFlags is an [Option] that calls the given [DefineFlagsFn] function and
// saves its returned values in [Runner].
func WithFlags[Holder any](f DefineFlagsFn[Holder]) Option {
	return func(r runnerInitializer) {
		r.withFlags(func(set *flag.FlagSet) {
			//nolint:errcheck // Safe because only the Runner type implements
			// the runnerInitializer interface.
			cr := r.(*Runner[Holder])
			cr.flags.holder, cr.flags.validator = f(set)
		})
	}
}

func (r *Runner[Holder]) withFlags(f func(set *flag.FlagSet)) {
	f(&r.flags.set)
}

// WithLoggerOptions is an [Option] that adds extra [zap.Option]'s to build
// the logger.
func WithLoggerOptions(options ...zap.Option) Option {
	return func(r runnerInitializer) {
		r.withLoggerOptions(options...)
	}
}

func (r *Runner[Holder]) withLoggerOptions(options ...zap.Option) {
	r.loggerOpts.Extra = options
}

// Run passes the given arguments to the command-line program, creates a logger,
// validates flags, and runs the command-line program itself via the given
// [RunFn] function.
//
// If no arguments are present, [os.Args][1:] are using.
func (r *Runner[Holder]) Run(
	run RunFn[Holder],
	args ...string,
) (err error) {
	var logger *zap.Logger
	errorWrapper := func() {
		if err != nil {
			cmdName := r.flags.set.Name()
			if cmdName != "" {
				err = fmt.Errorf("%s: %w", cmdName, err)
			}
			if logger != nil {
				logger.Error(err.Error())
			}
		}
	}

	defer errorWrapper()

	if len(args) == 0 {
		args = os.Args[1:]
	}

	if errParse := r.flags.set.Parse(args); errParse != nil {
		return errParse
	}

	logger, err = cmdlog.NewDevelopmentLogger(r.loggerOpts)
	if err != nil {
		return err
	}

	if errValidator := r.flags.validator(&r.flags.set, &r.flags.holder); errValidator != nil {
		return errValidator
	}

	return run(logger, &r.flags.holder)
}
