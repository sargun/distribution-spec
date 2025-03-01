EPOCH_TEST_COMMIT	:= 91d6d8466e68f1efff7977b63ad6f48e72245e05
CURRENT_COMMIT	:= $(shell git log --format="%H" -n 1)

DOCKER	?= $(shell command -v docker 2>/dev/null)
PANDOC	?= $(shell command -v pandoc 2>/dev/null)
GOLANGCILINT	?= $(shell command -v golangcli-lint 2>/dev/null)

OUTPUT_DIRNAME	?= output/
DOC_FILENAME	?= oci-distribution-spec

PANDOC_CONTAINER ?= ghcr.io/opencontainers/pandoc:2.9.2.1-8.fc33.x86_64@sha256:5d81ff930a043295a557be8b003ece2a33d14e91b28c50d368413b83372f8d28
ifeq "$(strip $(PANDOC))" ''
	ifneq "$(strip $(DOCKER))" ''
		PANDOC = $(DOCKER) run \
			-it \
			--rm \
			-v $(shell pwd)/:/input/:ro \
			-v $(shell pwd)/$(OUTPUT_DIRNAME)/:/$(OUTPUT_DIRNAME)/ \
			-u $(shell id -u) \
			--workdir /input \
			$(PANDOC_CONTAINER)
		PANDOC_SRC := /input/
		PANDOC_DST := /
	endif
endif

GOLANGCILINT_CONTAINER ?= ghcr.io/opencontainers/golangci-lint:v1.39.0@sha256:7bc0728c3034ee198e6ed439ad73d1512809a65aaccec2b2e2297c08582e5afd
ifeq "$(strip $(GOLANGCILINT))" ''
	ifneq "$(strip $(DOCKER))" ''
		GOLANGCILINT = $(DOCKER) run \
			-it \
			--rm \
			-v $(shell pwd)/:/input:ro \
			-e GOCACHE=/tmp/.cache \
			-e GO111MODULE=on \
			-e GOLANGCI_LINT_CACHE=/tmp/.cache \
			--entrypoint /bin/bash \
			-u $(shell id -u) \
			--workdir /input \
			$(GOLANGCILINT_CONTAINER)
		GOLANGCILINT_SRC := /input/
		GOLANGCILINT_DST := /
	endif
endif

DOC_FILES	:= spec.md
FIGURE_FILES	:=

test: .gitvalidation

# When this is running in travis, it will only check the travis commit range
.gitvalidation:
	@command -v git-validation >/dev/null 2>/dev/null || (echo "ERROR: git-validation not found. Consider 'make install.tools' target" && false)
ifdef TRAVIS_COMMIT_RANGE
	git-validation -q -run DCO,short-subject,dangling-whitespace
else
	git-validation -v -run DCO,short-subject,dangling-whitespace -range $(EPOCH_TEST_COMMIT)..HEAD
endif

docs: $(OUTPUT_DIRNAME)/$(DOC_FILENAME).pdf $(OUTPUT_DIRNAME)/$(DOC_FILENAME).html

ifeq "$(strip $(PANDOC))" ''
$(OUTPUT_DIRNAME)/$(DOC_FILENAME).pdf: $(DOC_FILES) $(FIGURE_FILES)
	$(error cannot build $@ without either pandoc or docker)
else
$(OUTPUT_DIRNAME)/$(DOC_FILENAME).pdf: $(DOC_FILES) $(FIGURE_FILES)
	mkdir -p $(OUTPUT_DIRNAME)/ && \
	$(PANDOC) -f gfm -t latex --pdf-engine=xelatex -V geometry:margin=0.5in,bottom=0.8in -V block-headings -o $(PANDOC_DST)$@ $(patsubst %,$(PANDOC_SRC)%,$(DOC_FILES))
	ls -sh $(realpath $@)

$(OUTPUT_DIRNAME)/$(DOC_FILENAME).html: header.html $(DOC_FILES) $(FIGURE_FILES)
	mkdir -p $(OUTPUT_DIRNAME)/ && \
	cp -ap img/ $(shell pwd)/$(OUTPUT_DIRNAME)/&& \
	$(PANDOC) -f gfm -t html5 -H $(PANDOC_SRC)header.html --standalone -o $(PANDOC_DST)$@ $(patsubst %,$(PANDOC_SRC)%,$(DOC_FILES))
	ls -sh $(realpath $@)
endif

header.html: .tool/genheader.go specs-go/version.go
	go mod init && \
	go run .tool/genheader.go > $@

install.tools: .install.gitvalidation

.install.gitvalidation:
	go get -u github.com/vbatts/git-validation

conformance: conformance-test conformance-binary

conformance-test:
	$(GOLANGCILINT) -c 'cd conformance && golangci-lint run -v'

conformance-binary: $(OUTPUT_DIRNAME)/conformance.test

$(OUTPUT_DIRNAME)/conformance.test:
	cd conformance && \
		CGO_ENABLED=0 go test -c -o $(shell pwd)/$(OUTPUT_DIRNAME)/conformance.test \
			--ldflags="-X github.com/opencontainers/distribution-spec/conformance.Version=$(CURRENT_COMMIT)"
