.PHONY: build test tidy install

BINARY=mcweb-hostd
CMD=./cmd/mcweb-hostd

build:
	go build -o $(BINARY) $(CMD)

test:
	go test ./...

tidy:
	go mod tidy

install: build
	install -m 755 $(BINARY) /usr/local/bin/$(BINARY)
