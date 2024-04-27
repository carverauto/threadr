# Define variables
KO_DOCKER_REPO := ghcr.io/carverauto/threadr-irc
VERSION := v0.0.27

# Default target
all: build

# Build target
build:
	@export KO_DOCKER_REPO=$(KO_DOCKER_REPO) && export VERSION=$(VERSION) && ko build --bare --tags $(VERSION) ./

.PHONY: all build

