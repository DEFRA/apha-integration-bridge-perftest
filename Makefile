SHELL := /bin/bash

.PHONY: help gui perf-test

help:
	@echo "Available commands:"
	@echo "  make gui"
	@echo "  make perf-test"

gui:
	./bridge-perf gui

perf-test:
	./bridge-perf
