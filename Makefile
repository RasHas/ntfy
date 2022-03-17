VERSION := $(shell git describe --tag)

.PHONY:

help:
	@echo "Typical commands:"
	@echo "  make check                   - Run all tests, vetting/formatting checks and linters"
	@echo "  make build-snapshot install  - Build latest and install to local system"
	@echo
	@echo "Test/check:"
	@echo "  make test                    - Run tests"
	@echo "  make race                    - Run tests with -race flag"
	@echo "  make coverage                - Run tests and show coverage"
	@echo "  make coverage-html           - Run tests and show coverage (as HTML)"
	@echo "  make coverage-upload         - Upload coverage results to codecov.io"
	@echo
	@echo "Lint/format:"
	@echo "  make fmt                     - Run 'go fmt'"
	@echo "  make fmt-check               - Run 'go fmt', but don't change anything"
	@echo "  make vet                     - Run 'go vet'"
	@echo "  make lint                    - Run 'golint'"
	@echo "  make staticcheck             - Run 'staticcheck'"
	@echo
	@echo "Build main client/server:"
	@echo "  make build                   - Build (using goreleaser, requires clean repo)"
	@echo "  make build-snapshot          - Build snapshot (using goreleaser, dirty repo)"
	@echo "  make build-simple            - Quick & dirty build (using go build, without goreleaser)"
	@echo "  make clean                   - Clean build folder"
	@echo
	@echo "Build web app:"
	@echo "  make web                     - Build the web app"
	@echo "  make web-deps                - Install web app dependencies (npm install the universe)"
	@echo "  make web-build               - Actually build the web app"
	@echo
	@echo "Build documentation:"
	@echo "  make docs                     - Build the documentation"
	@echo "  make docs-deps                - Install Python dependencies (pip3 install)"
	@echo "  make docs-build               - Actually build the documentation"
	@echo
	@echo "Releasing (requires goreleaser):"
	@echo "  make release                 - Create a release"
	@echo "  make release-snapshot        - Create a test release"
	@echo
	@echo "Install locally (requires sudo):"
	@echo "  make install                 - Copy binary from dist/ to /usr/bin"
	@echo "  make install-deb             - Install .deb from dist/"
	@echo "  make install-lint            - Install golint"


# Documentation

docs-deps: .PHONY
	pip3 install -r requirements.txt

docs-build: .PHONY
	mkdocs build

docs: docs-deps docs-build


# Web app

web-deps:
	cd web \
		&& npm install \
		&& node_modules/svgo/bin/svgo src/img/*.svg

web-build:
	cd web \
		&& npm run build \
		&& mv build/index.html build/app.html \
		&& rm -rf ../server/site \
		&& mv build ../server/site \
		&& rm \
			../server/site/config.js \
			../server/site/asset-manifest.json

web: web-deps web-build


# Test/check targets

check: test fmt-check vet lint staticcheck

test: .PHONY
	go test -v $(shell go list ./... | grep -vE 'ntfy/(test|examples|tools)')

race: .PHONY
	go test -race $(shell go list ./... | grep -vE 'ntfy/(test|examples|tools)')

coverage:
	mkdir -p build/coverage
	go test -race -coverprofile=build/coverage/coverage.txt -covermode=atomic $(shell go list ./... | grep -vE 'ntfy/(test|examples|tools)')
	go tool cover -func build/coverage/coverage.txt

coverage-html:
	mkdir -p build/coverage
	go test -race -coverprofile=build/coverage/coverage.txt -covermode=atomic $(shell go list ./... | grep -vE 'ntfy/(test|examples|tools)')
	go tool cover -html build/coverage/coverage.txt

coverage-upload:
	cd build/coverage && (curl -s https://codecov.io/bash | bash)


# Lint/formatting targets

fmt:
	gofmt -s -w .

fmt-check:
	test -z $(shell gofmt -l .)

vet:
	go vet ./...

lint:
	which golint || go install golang.org/x/lint/golint@latest
	go list ./... | grep -v /vendor/ | xargs -L1 golint -set_exit_status

staticcheck: .PHONY
	rm -rf build/staticcheck
	which staticcheck || go install honnef.co/go/tools/cmd/staticcheck@latest
	mkdir -p build/staticcheck
	ln -s "go" build/staticcheck/go
	PATH="$(PWD)/build/staticcheck:$(PATH)" staticcheck ./...
	rm -rf build/staticcheck


# Building targets

build-deps: docs web
	which arm-linux-gnueabi-gcc || { echo "ERROR: ARMv6/v7 cross compiler not installed. On Ubuntu, run: apt install gcc-arm-linux-gnueabi"; exit 1; }
	which aarch64-linux-gnu-gcc || { echo "ERROR: ARM64 cross compiler not installed. On Ubuntu, run: apt install gcc-aarch64-linux-gnu"; exit 1; }

build: build-deps
	goreleaser build --rm-dist --debug

build-snapshot: build-deps
	goreleaser build --snapshot --rm-dist --debug

build-simple: .PHONY
	mkdir -p dist/ntfy_linux_amd64 server/docs server/site
	touch server/docs/index.html
	touch server/site/app.html
	export CGO_ENABLED=1
	go build \
		-o dist/ntfy_linux_amd64/ntfy \
		-tags sqlite_omit_load_extension,osusergo,netgo \
		-ldflags \
		"-linkmode=external -extldflags=-static -s -w -X main.version=$(VERSION) -X main.commit=$(shell git rev-parse --short HEAD) -X main.date=$(shell date +%s)"

clean: .PHONY
	rm -rf dist build server/docs server/site


# Releasing targets

release-check-tags:
	$(eval LATEST_TAG := $(shell git describe --abbrev=0 --tags | cut -c2-))
	if ! grep -q $(LATEST_TAG) docs/install.md; then\
	 	echo "ERROR: Must update docs/install.md with latest tag first.";\
	 	exit 1;\
	fi
	if grep -q XXXXX docs/releases.md; then\
		echo "ERROR: Must update docs/releases.md, found XXXXX.";\
		exit 1;\
	fi
	if ! grep -q $(LATEST_TAG) docs/releases.md; then\
		echo "ERROR: Must update docs/releases.mdwith latest tag first.";\
		exit 1;\
	fi

release: build-deps release-check-tags check
	goreleaser release --rm-dist --debug

release-snapshot: build-deps
	goreleaser release --snapshot --skip-publish --rm-dist --debug


# Installing targets

install:
	sudo rm -f /usr/bin/ntfy
	sudo cp -a dist/ntfy_linux_amd64/ntfy /usr/bin/ntfy

install-deb:
	sudo systemctl stop ntfy || true
	sudo apt-get purge ntfy || true
	sudo dpkg -i dist/ntfy_*_linux_amd64.deb
