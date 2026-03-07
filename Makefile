# This file is licensed under the terms of the MIT License
#
# Copyright (c) 2026 Pavel Tsayukov p.tsayukov@gmail.com
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# ============================================================================ #
# This is a multi-platform Makefile for Golang projects, trying to support both
# Unix-like and Windows operating systems.
#
# It is very much inspired by the Makefile made by Alex Edwards. Check that out:
#  - https://www.alexedwards.net/blog/a-time-saving-makefile-for-your-go-projects
#  - https://gist.github.com/alexedwards/3b40775846535d0014ab1ff477e4a568
#
#                                  HOW TO USE
#
# The simplest way is to copy the Makefile into your project and to modify it
# according to your needs.
#
# The more extensible way is to create a subtree by importing its content from
# the repository, e.g.:
#
#   git subtree --squash -P scripts/make add git@github.com:tsayukov/golang-multi-platform-makefile.git main
#
# that creates the scripts/make directory and put the Makefile into it. Then you
# can include the Makefile in your top-level Makefile:
#
#   include scripts/make/Makefile
#
# Getting updates can be done using the command (if the working tree
# has no modification!):
#
#   git subtree --squash -P scripts/make pull git@github.com:tsayukov/golang-multi-platform-makefile.git main
#
# After the deed is done, type the command `make help` or just `make`.
#
#                                  STYLE GUIDE
#                          (Recommendations, not rules)
#
# All internal variables and function-like variables are named in camelCase
# starting with the 'gm' prefix that stands for 'Go Makefile'. These variables
# are defined using the override directive and are not intended to change.
#
# Variables that imply changes are named in UPPERCASE_WITH_UNDERSCORES.
#
# Targets are named in lowercase. The words can be separated by slash or hyphen.
# You can use a slash to group similar targets and use a hyphen instead of a space.
#
#                    HOW TO WRITE DOCUMENTATION FOR TARGETS
#
# Every comment line that starts with two '#' is parsed by the 'help' target
# as part of the help message:
#  - use '##:' to output an empty line;
#  - use '##<target>:<description>' for a single-line description;
#  - use '##<target>:<description>' with the following '##:<description>',
#    each on the next line, for a multiline description.
#
# Whitespaces between '##', '<target>', ':', and '<description>' do not matter.
#
# A standalone '##:<description>' with the surrounding '##:' at the top
# and bottom can be used to write a header, e.g., 'Variables', 'Build', etc.
#
#                          OPERATING SYSTEM DETECTION
#
# To detect the operating system:
#
# 1. Check whether the environment variable PATH contains the path separator:
#  - in Windows:
    override gmSemicolon := ;
#  - in a Unix-like operating system:
    override gmColon     := :
# Unlikely, but the PATH might contain only one element or a path with
# a semicolon in a Unix-like operating system. It can also be passed
# via the command line to prepend it with the specific user path.
#
# 2. Check the environment variable OS that holds the string 'Windows_NT'
# on the Windows NT family. However, the OS variable can be overwritten.
#
# 3. Call the `uname` command to get the name of the current operating system.
    override gmUnameOrUnknown := sh -c 'uname 2>/dev/null || echo Unknown'
# Transform the Cygwin/MSYS verbose output of `uname` to 'Cygwin'/'MSYS'.
# See: https://stackoverflow.com/a/52062069/10537247
    override gmShortenOSName = \
        $(patsubst CYGWIN%,Cygwin,\
            $(patsubst MSYS%,MSYS,\
                $(patsubst MINGW%,MSYS,\
                    $1\
                )\
            )\
        )
#
# Nevertheless, it is unlikely that these pitfalls will occur in most cases.
# Otherwise, pass the OS variable into the `make` call to specify the current
# operating system:
#   make OS=<operating system name> [...]
#
    ifeq ($(origin OS),command line)
        override gmOS := $(OS)
    else ifeq ($(OS),Windows_NT)
        # Distinguish between native Windows and Cygwin/MSYS.
        ifneq (,$(findstring $(gmSemicolon),$(PATH))) # if semicolon is in PATH
            override gmOS := Windows
        else
            override gmOS := $(call gmShortenOSName,$(shell $(gmUnameOrUnknown)))
        endif
    else
        override gmOS := $(shell $(gmUnameOrUnknown))
    endif
#
# Use the gmOS variable to match the detected operating system against
# Windows, Linux, Darwin, etc.
#
#                                 CONFIGURATION
#
# Explicitly say what the target is default; change it as necessary.
    .DEFAULT_GOAL := help
#
# Choosing the appropriate shell, path separator, and list separator.
    ifeq ($(gmOS),Unknown)
        $(error unknown operating system)
    else ifeq ($(gmOS),Windows)
        SHELL := pwsh.exe
        override gmPathSep := \\
        override gmListSep := $(gmSemicolon)
    else
        SHELL := /bin/sh
        override gmPathSep := /
        override gmListSep := $(gmColon)
    endif
#
# The project root containing the Makefile as an absolute path.
# NOTE: the first word of MAKEFILE_LIST should be used in cases where
# a top-level Makefile includes this file.
    override gmProjectRoot := $(subst /,$(gmPathSep),$(dir $(abspath $(firstword $(MAKEFILE_LIST)))))
#
#                                     TIPS
#
# 1. To split a PowerShell command line over multiple lines in a recipe
# use a comment block with a backslash inside:
#   @ do things <#\
#   #> do other things
#
# You can also wrap a command by the gmRun call (see below in "Logging")
# and split it by a backslash.
#   @ $(call gmRun,Do things and other things,\
#       do things \
#       do other things \
#   )
#
# 2. Colorful output:
#   .PHONY: target
#   target:
#   	@ $(call gmGo,Running $@...)
#   	@ $(call gmOK,Running $@ - done)
#   	@ $(call gmWarn,Running $@ - warning)
#   	@ $(call gmErr,Running $@ - failed)
#
    ifeq ($(gmOS),Windows)
        override gmRed    := Red
        override gmGreen  := Green
        override gmBlue   := Blue
        override gmYellow := Yellow
        override gmColorText = Write-Host "$2" -ForegroundColor $1 -NoNewline
    else
        override gmRed    := \\033[0;31m
        override gmGreen  := \\033[0;32m
        override gmBlue   := \\033[0;34m
        override gmYellow := \\033[1;33m
        override gmColorText = printf "%b%s%b" "$1" "$2" "\033[0m"
    endif

    override gmGo   = $(call gmColorText,$(gmBlue),> ) && echo "$1"
    override gmOK   = $(call gmColorText,$(gmGreen),v ) && echo "$1"
    override gmWarn = $(call gmColorText,$(gmYellow),!! ) && echo "$1"
    override gmErr  = $(call gmColorText,$(gmRed),x ) && echo "$1"
#
# 3. Logging:
#
#   .PHONY: do
#   do:
#   	@ $(call gmRun,Do something,\
#           echo "The did is done" \
#       )
#
    ifeq ($(gmOS),Windows)
        override gmRun = \
            $(call gmGo,$1...); $2; if ($$?) { \
                $(call gmOK,$1 - done) \
            } else { \
                $(call gmErr,$1 - failed); \
                exit 1 \
            }
    else
        override gmRun = \
            $(call gmGo,$1...); \
            $2; if [ $$? = 0 ]; \
            then $(call gmOK,$1 - done); \
	        else $(call gmErr,$1 - failed) \
	             && exit 1; \
	        fi
    endif
#
# 4. Auxiliary function-like variables:
#
# 4.1. There are convenient definitions of the comma and space variables:
    override gmComma := ,
    override gmEmpty :=
    override gmSpace := $(gmEmpty) $(gmEmpty)
# They can be used to replace space-separated words with comma-separated words,
# i.e., to pass them into a PowerShell command:
    override gmSpaceSepToCommaSepList = $(subst $(gmSpace),$(gmComma),$(strip $1))
#
# 4.2. Reverse space-separated words (https://stackoverflow.com/a/786530/10537247).
    override gmReverse = $(if $1,$(call gmReverse,$(wordlist 2,$(words $1),$1))) $(firstword $1)
#
# 4.3. Set an environment variable in the "key=value" format. E.g.:
#   $(call gmEnv,CGO_ENABLED=0) go env CGO_ENABLED
# will print 0.
    ifeq ($(gmOS),Windows)
        override gmEnv = $$env:$1; #
    else
        override gmEnv = $1 #
    endif
# ============================================================================ #

# NOTE: the blank line below is necessary to get the same help message
# on different operating systems.
##:
## help: print this help message and exit
.PHONY: help
help:
	@ $(info )
	@ $(info :: Go Makefile)
	@ $(info :: OS: $(gmOS))
	@ $(info :: SHELL: $(SHELL))
	@ $(info )
ifeq ($(gmOS),Windows)
    # Hack: replace two '#' with the NULL character to force ConvertFrom-Csv
    # to print empty lines.
	@ Write-Host "Targets:" -NoNewline; <#\
 #> (Get-Content $(call gmSpaceSepToCommaSepList,$(call gmReverse,$(MAKEFILE_LIST)))) <#\
 #>     -match "^##" -replace "^##","$$([char]0x0)" <#\
 #> | ConvertFrom-Csv -Delimiter ":" -Header Target,Description <#\
 #> | Format-Table <#\
 #>     -AutoSize -HideTableHeaders <#\
 #>     -Property @{Expression=" "},Target,@{Expression=" "},Description
else
	@ echo 'Targets:' \
	&& sed --quiet 's/^##//p' $(call gmReverse,$(MAKEFILE_LIST)) \
	| sed --expression='s/[ \t]*:[ \t]*/:/' \
    | column --table --separator ':' \
    | sed --expression='s/^/ /' \
    && echo
endif

# ============================================================================ #
##:
##:                                 Variables
##:
# These variables can be changed:
#  - by editing this file (not encouraged);
#  - by overriding them in the top-level Makefile that includes this file
#    (recommended):
#    VAR := your value
#  - by passing them into the `make` call:
#    make <variable_1>=<value_1> <variable_2>=<value_2> [...]
#
# To generate a target that prints the value of a variable,
# as gmVariableGetterRule does by default, use the list below and append
# it with the variable name:
#   override gmVariables += <variable name>
    override gmVariables :=
# When you are done to define your variables call gmMakeVariableGetters
# to generate the rules:
#   $(call gmMakeVariableGetters)
override define gmMakeVariableGetters
    $(foreach var,$(gmVariables), \
        $(eval \
            $(call gmVariableGetterRule,$(var)) \
        ) \
    ); $(eval $(call gmVariablesClear))
endef
# It also cleans the last gmVariables list, so you can define other variables
# separately and do the target generation again.
override define gmVariablesClear
    override gmVariables :=
endef
# If you want a different behavior for your variables, just copy the definition
# below, paste before the gmMakeVariableGetters call, and change the recipe.
override define gmVariableGetterRule
.PHONY: $1
$1:
	@ echo "$$($1)"
endef
# ============================================================================ #

## BINARY_DIR: get the directory with binaries
BINARY_DIR := bin
override gmVariables += BINARY_DIR

## GOBIN: get the absolute path where the `go install` command installs binaries;
##      : GOBIN will be exported to child processes and prepended to PATH
export GOBIN ?= $(gmProjectRoot)$(BINARY_DIR)
export PATH  := $(GOBIN)$(gmListSep)$(PATH)
override gmVariables += GOBIN

## GOOS: get the target's operation system;
##     : GOOS will be exported to child processes
export GOOS ?= $(shell go env GOOS)
override gmVariables += GOOS

## GOARCH: get the target's architecture;
##       : GOARCH will be exported to child processes
export GOARCH ?= $(shell go env GOARCH)
override gmVariables += GOARCH

## PACKAGE_PATHS: get a list of paths of packages to build;
##              : they may be relative to the current directory
##              : (e.g., "." or "cmd/tool")
PACKAGE_PATHS := .
override gmVariables += PACKAGE_PATHS

## BUILD_ARGS: get a list of build flags using for the `go build` command
BUILD_ARGS := \
    -trimpath
override gmVariables += BUILD_ARGS

## TEST_ARGS: get a list of build/test flags using for the `go test` command
TEST_ARGS := \
    -v \
    -race
override gmVariables += TEST_ARGS

## AUDIT_RULES: get a list of targets each of which is invoked for the audit
##            : target
AUDIT_RULES := \
    mod/tidy-diff \
    mod/verify \
    fmt/no-dirty \
    golangci-lint
override gmVariables += AUDIT_RULES

$(call gmMakeVariableGetters)

# ============================================================================ #
#                                    Helpers
# ============================================================================ #

# gmChoiceOrErr prompts the user to choose between two options:
# the second one always terminates the 'make' execution with the given error.
#  $1: a prompt prefix
#  $2: a first option
#  $3: a second option
#  $4: a error message
ifeq ($(gmOS),Windows)
    override gmChoiceOrErr = \
        if ((Read-Host -Prompt "$1 [$2/$3]") -cne "$2") { \
            $(call gmErr,$4); \
            exit 1 \
        }
else
	override gmChoiceOrErr = \
	    read -r -p '$1 [$2/$3] ' answer && [ $${answer:-$3} = '$2' ] || ( \
            $(call gmErr,$4) \
            && exit 1 \
        )
endif

# gmEmptyOrErr runs the given command and terminates the 'make' execution
# with the given error if the command output is not empty.
#  $1: a error message
#  $2: a command to check
ifeq ($(gmOS),Windows)
    override gmEmptyOrErr = \
        if (![string]::IsNullOrEmpty("$(shell $2)")) { \
            $(call gmErr,$1); \
            exit 1 \
        }
else
    override gmEmptyOrErr = \
        test -z '$(shell $2)' || ( \
            $(call gmErr,$1) \
            && exit 1 \
        )
endif

.PHONY: gm/confirm
gm/confirm:
	@ $(call gmChoiceOrErr,Are you sure?,y,N,The choice is not confirmed. Abort!)

.PHONY: gm/git/no-dirty
gm/git/no-dirty:
	@ $(call gmEmptyOrErr,There are untracked/unstaged/uncommitted changes!,\
        git status --porcelain \
    )

.PHONY: gm/git/no-staged
gm/git/no-staged:
	@ $(call gmEmptyOrErr,There are staged changes!,\
		$(call gmGitNoStagedImpl) \
    )

ifeq ($(gmOS),Windows)
    override gmGitNoStagedImpl = if ((git status --porcelain | Out-String) -match "^(M|A).* ") { "no empty" } else { "" }
else
    override gmGitNoStagedImpl = git status --porcelain | grep -E "^(M|A).* "
endif

.PHONY: gm/create/binary_dir
gm/create/binary_dir:
ifeq ($(gmOS),Windows)
	@ [void](New-Item "$(BINARY_DIR)" -ItemType Directory -Force)
else
	@ mkdir -p "$(BINARY_DIR)"
endif

# ============================================================================ #
##:
##:                                   Build
##:
# ============================================================================ #

## build: build all packages (see the PACKAGE_PATHS variable)
.PHONY: build
build: gm/create/binary_dir
	@ $(foreach packagePath,$(PACKAGE_PATHS), \
        $(let package,$(notdir $(packagePath)), \
            $(call gmRun,Building $(package), \
                $(call gmEnv,CGO_ENABLED=0) \
                go build \
                    $(BUILD_ARGS) \
                    -o=$(BINARY_DIR)/$(package) \
                    $(package) \
            ) \
        ) \
    )

## mod/download: download modules to local cache
.PHONY: mod/download
mod/download:
	@ $(call gmRun,Downloading modules to local cache,\
        go mod download -x \
    )

## mod/tidy-diff: check missing and unused modules without modifying
##              : the `go.mod` and `go.sum` files
.PHONY: mod/tidy-diff
mod/tidy-diff:
	@ $(call gmRun,Checking missing and unused modules,\
        go mod tidy -diff \
    )

## mod/tidy: add missing modules and remove unused modules
.PHONY: mod/tidy
mod/tidy:
	@ $(call gmRun,Adding missing modules and removing unused modules,\
        go mod tidy -v \
    )

## clean: remove files from the binary directory
.PHONY: clean
clean:
	@ $(call gmRun,Cleaning $(BINARY_DIR),\
        $(call gmCleanImpl) \
    )

ifeq ($(gmOS),Windows)
    override gmCleanImpl = \
        if (Test-Path "$(BINARY_DIR)" -PathType Container) { \
            Remove-Item "$(BINARY_DIR)\*" -Recurse -Force \
        }
else
    override gmCleanImpl = rm -rf $(BINARY_DIR)/*
endif

# ============================================================================ #
##:
##:                              Quality control
##:
# ============================================================================ #

## audit: run quality control checks
##      : (see the AUDIT_RULES variable to learn what targets will be called)
.PHONY: audit
audit: $(AUDIT_RULES) ;

## test: run all tests
##     : (see the TEST_ARGS variable to learn what flags will be applied)
.PHONY: test
test:
	@ $(call gmRun,Running all tests,\
        $(if $(firstword $(filter -race,$(TEST_ARGS))),$(call gmEnv,CGO_ENABLED=1)) \
        go test $(TEST_ARGS) ./... \
    )

## test/cover: run all tests with coverage (see the test target)
.PHONY: test/cover
test/cover: gm/create/binary_dir
	@ $(call gmRun,Running all tests with coverage,\
        $(if $(firstword $(filter -race,$(TEST_ARGS))),$(call gmEnv,CGO_ENABLED=1)) \
        go test $(TEST_ARGS) -coverprofile="$(BINARY_DIR)/coverage.out" ./... \
    )

## test/cover/html: display coverage in a browser
.PHONY: test/cover/html
test/cover/html: test/cover
	@ go tool cover -html="$(BINARY_DIR)/coverage.out"

## test/cover/endpoint-badge: generate a JSON file for Endpoint Badge;
##                          : file io.shields.badges.endpoint.json;
##                          : see shields.io/badges/endpoint-badge
.PHONY: test/cover/endpoint-badge
test/cover/endpoint-badge: test/cover
	@ $(call gmRun,Generating $(gmTestCoverEndpointBadgeJSON),\
        $(call gmTestCoverEndpointBadgeImpl) \
    )

override gmTestCoverEndpointBadgeJSON := io.shields.badges.endpoint.coverage.json
override gmTestCoverEndpointBadgeMinColorRange := 50
override gmTestCoverEndpointBadgeMaxColorRange := 95

ifeq ($(gmOS),Windows)
    override gmTestCoverEndpointBadgeImpl = \
        $$total = ( \
            go tool cover -func="$(BINARY_DIR)/coverage.out" \
            | Select-String '^total:' -Raw \
            | Select-String '[0-9]+\.[0-9]+' \
        ).Matches.Value; \
        $$min = [double]::Parse( \
            "$(gmTestCoverEndpointBadgeMinColorRange)", \
            [cultureinfo]::InvariantCulture); \
        $$max = [double]::Parse( \
            "$(gmTestCoverEndpointBadgeMaxColorRange)", \
            [cultureinfo]::InvariantCulture); \
        $$val = [math]::Clamp( \
            [double]::Parse($$total, [cultureinfo]::InvariantCulture), \
            $$min, $$max); \
        $$hue = [math]::Floor((($$val - $$min) / ($$max - $$min)) * 120); \
        "{`"schemaVersion`":1,`"label`":`"Coverage`",`"message`":`"$$total%`",`"color`":`"hsl($$hue,100%,40%)`"}" \
        | Out-File -Path $(gmTestCoverEndpointBadgeJSON) -Encoding utf8 -Force -NoNewline
else
    override gmTestCoverEndpointBadgeImpl = \
        total=$$(\
            go tool cover -func="$(BINARY_DIR)/coverage.out" \
            | grep -E '^total' \
            | grep -Eo '[0-9]+\.[0-9]+' \
        ); \
        min=$(gmTestCoverEndpointBadgeMinColorRange); \
        max=$(gmTestCoverEndpointBadgeMaxColorRange); \
        hue=$$(\
           echo "\
           scale = 2; \
           val = $$total; \
           if (val < $$min) val = $$min; \
           if (val > $$max) val = $$max; \
           hue = ((val - $$min) / ($$max - $$min)) * 120; \
           scale = 0; hue / 1 \
           " | bc -l \
        ); \
        echo -n \
        "{\"schemaVersion\":1,\"label\":\"Coverage\",\"message\":\"$$total%\",\"color\":\"hsl($$hue,100%,40%)\"}" \
        > $(gmTestCoverEndpointBadgeJSON)
endif

## mod/verify: verify that dependencies have expected content
.PHONY: mod/verify
mod/verify:
	@ $(call gmRun,Verifying dependencies,\
        go mod verify \
    )

## fmt/no-dirty: check package sources whose formatting differs from gofmt
.PHONY: fmt/no-dirty
fmt/no-dirty:
	@ $(call gmEmptyOrErr,Package sources is unformatted,\
        gofmt -d . \
    )

## fmt: gofmt (reformat) package sources
.PHONY: fmt
fmt:
	@ $(call gmRun,Reformatting package sources,\
        go fmt ./... \
    )

## vet: report likely mistakes in packages
.PHONY: vet
vet:
	@ $(call gmRun,Running go vet,\
        go vet ./... \
    )

## golangci-lint: a fast linters runner for Go
.PHONY: golangci-lint
golangci-lint:
	@ $(call gmRun,Running golangci-lint,\
        golangci-lint run ./... \
    )
