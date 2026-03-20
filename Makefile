SHELL := /bin/bash

.PHONY: help gui-dev gui-test gui-perf-test gui-preprod dev test perf-test preprod

help:
	@echo "Available commands:"
	@echo "  make gui-dev"
	@echo "  make gui-test"
	@echo "  make gui-perf-test"
	@echo "  make gui-preprod"
	@echo "  make dev"
	@echo "  make test"
	@echo "  make perf-test"
	@echo "  make preprod"

gui-dev:
	./bridge-perf gui dev

gui-test:
	./bridge-perf gui test

gui-perf-test:
	./bridge-perf gui perf-test

gui-preprod:
	./bridge-perf gui preprod

dev:
	./bridge-perf dev

test:
	./bridge-perf test

perf-test:
	./bridge-perf perf-test

preprod:
	./bridge-perf preprod
