SHELL := /bin/bash
APP_NAME := DeskPet
BUILD_DIR := .build/release
DIST := dist
BUNDLE := $(DIST)/$(APP_NAME).app

.PHONY: help build test run app sign dmg verify clean lint-macros validate-sample perf

help:
	@echo "make build            编译 release"
	@echo "make test             跑零依赖自测（退出码非 0 即失败）"
	@echo "make app              组装 dist/DeskPet.app"
	@echo "make run              组装并启动 app"
	@echo "make sign             ad-hoc 签名"
	@echo "make dmg              产出 dist/DeskPet.dmg"
	@echo "make verify           校验签名与镜像"
	@echo "make lint-macros      检查是否误用 @State / @Bindable"
	@echo "make ui-check         离屏渲染自检（像素统计）"
	@echo "make perf             采样 30s 的 CPU / 内存"
	@echo "make clean            清理产物"

build:
	swift build -c release

test: build
	$(BUILD_DIR)/DeskPetSelfTest

app: build
	@bash scripts/bundle.sh

sign: app
	@codesign --force --sign - --timestamp=none $(BUNDLE)
	@codesign -dv $(BUNDLE) 2>&1 | grep -E "Identifier|Signature|Format" || true

run: app
	@open $(BUNDLE)

dmg: sign
	@bash scripts/dmg.sh

verify: sign
	@echo "== codesign =="; codesign -dv $(BUNDLE) 2>&1 | head -5 || true
	@echo "== spctl（预期 rejected：无 Developer ID）=="; spctl -a -vvv -t exec $(BUNDLE) 2>&1 | head -2 || true
	@echo "== 包内 webp 数量（必须为 0）=="; find $(BUNDLE) -name "*.webp" | wc -l

lint-macros:
	@if grep -rn --include=*.swift -E '@State\b|@Bindable\b' Sources/ ; then \
		echo "ERROR: CLT 环境下 @State/@Bindable 编译不过，请改用 ObservableObject" >&2; exit 1; \
	else echo "OK: 没有误用 @State/@Bindable"; fi

ui-check: build
	@$(BUILD_DIR)/DeskPet --self-check-ui

perf:
	@PID=$$(pgrep -x $(APP_NAME) | head -1); \
	if [ -z "$$PID" ]; then echo "app 未运行，先 make run" >&2; exit 1; fi; \
	echo "采样 30s（每 3s 一次）：PID=$$PID"; \
	for i in $$(seq 1 10); do \
		ps -o %cpu=,rss= -p $$PID | awk -v i=$$i '{printf "  %2ds  CPU %5.1f%%  RSS %6.1f MB\n", i*3, $$1, $$2/1024}'; \
		sleep 3; \
	done

clean:
	rm -rf .build $(DIST)
