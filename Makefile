SHELL := /bin/bash

.PHONY: help gui-dev smoke-dev boundary-dev boundary-test boundary-perf boundary-preprod

help:
	@echo "Available commands:"
	@echo "  make gui-dev"
	@echo "  make smoke-dev"
	@echo "  make boundary-dev"
	@echo "  make boundary-test"
	@echo "  make boundary-perf"
	@echo "  make boundary-preprod"

gui-dev:
	BRIDGE_PERF_AUTO_INSTALL_JAVA=1 ./bridge-perf gui dev

smoke-dev:
	BRIDGE_PERF_AUTO_INSTALL_JAVA=1 ./bridge-perf smoke dev

boundary-dev:
	BRIDGE_PERF_AUTO_INSTALL_JAVA=1 ./bridge-perf boundary dev

boundary-test:
	BRIDGE_PERF_AUTO_INSTALL_JAVA=1 ./bridge-perf boundary test

boundary-perf:
	BRIDGE_PERF_AUTO_INSTALL_JAVA=1 ./bridge-perf boundary perf-test

boundary-preprod:
	BRIDGE_PERF_AUTO_INSTALL_JAVA=1 ./bridge-perf boundary preprod
