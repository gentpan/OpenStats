PROJECT  := OpenStats.xcodeproj
SCHEME   := OpenStats
CONFIG   ?= Debug
DERIVED  := build/DerivedData
APP      := $(DERIVED)/Build/Products/$(CONFIG)/OpenStats.app

# 与 QuotaBar 相同：钥匙串里有 Developer ID 证书就自动用它签名，否则退回 ad-hoc（仅限本机）。
# 也可以用 SIGN_ID="..." 显式指定。
SIGN_ID  ?= $(shell security find-identity -v -p codesigning 2>/dev/null | grep 'Developer ID Application' | head -1 | sed -E 's/.*"(.*)".*/\1/')
TEAM_ID  := $(shell echo '$(SIGN_ID)' | sed -nE 's/.*\(([A-Z0-9]+)\)$$/\1/p')
ifneq ($(strip $(TEAM_ID)),)
# Release 加安全时间戳，公证要求如此，证书过期后签名依然有效
SIGN_FLAGS := CODE_SIGN_IDENTITY="$(SIGN_ID)" DEVELOPMENT_TEAM=$(TEAM_ID) \
	$(if $(filter Release,$(CONFIG)),OTHER_CODE_SIGN_FLAGS=--timestamp CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO)
endif

.PHONY: generate build run install release stop test snapshot open clean

## 由 project.yml 生成 Xcode 工程
generate:
	xcodegen generate --quiet

## 编译 App（含辅助工具）
build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		-derivedDataPath $(DERIVED) -destination 'platform=macOS' -quiet $(SIGN_FLAGS) build

## 编译并启动（会先结束正在运行的 OpenStats）
run: build stop
	open $(APP)

## 以 Release 构建安装到 /Applications 并启动（覆盖旧版本，保留偏好设置）
install:
	$(MAKE) build CONFIG=Release
	-pkill -x OpenStats
	rm -rf /Applications/OpenStats.app
	ditto $(DERIVED)/Build/Products/Release/OpenStats.app /Applications/OpenStats.app
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/OpenStats.app
	open /Applications/OpenStats.app

## 发布：签名、公证、装订、打包 DMG，生成 Homebrew cask（见 Scripts/release.sh）
release:
	./Scripts/release.sh

stop:
	-pkill -x OpenStats

## 单元测试
test:
	cd Packages/OpenStatsKit && swift test

## 用本机实时数据渲染各页面截图到 build/snapshots
snapshot: build
	$(APP)/Contents/MacOS/OpenStats --snapshot build/snapshots

open: generate
	open $(PROJECT)

clean:
	rm -rf build
