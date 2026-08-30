.DEFAULT_GOAL := help
SHELL := /bin/bash

.PHONY: help check test install uninstall probe

help:
	@printf '\n  agentawake\n\n'
	@printf '  make check      syntax-check scripts and plists\n'
	@printf '  make test       run behavior tests without changing sleep\n'
	@printf '  make install    install or update the root daemons\n'
	@printf '  make uninstall  remove the daemons and restore normal sleep\n'
	@printf '  make probe      verify pmset and optional Pager access\n\n'

check:
	@bash -n agentawake agentawake-pslog install.sh uninstall.sh probe.sh tests/run.sh
	@plutil -lint com.albastov.agentawake.plist com.albastov.agentawake-pslog.plist

test: check
	@bash tests/run.sh

install:
	@sudo ./install.sh

uninstall:
	@sudo ./uninstall.sh

probe:
	@sudo ./probe.sh
