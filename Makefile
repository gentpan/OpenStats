PROJECT  := OpenStats.xcodeproj
SCHEME   := OpenStats
CONFIG   ?= Debug
DERIVED  := build/DerivedData
APP      := $(DERIVED)/Build/Products/$(CONFIG)/OpenStats.app

.PHONY: generate build run install stop test snapshot open clean

## 由 project.yml 生成 Xcode 工程
generate:
	xcodegen generate --quiet

## 编译 App（含辅助工具）
build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		-derivedDataPath $(DERIVED) -destination 'platform=macOS' -quiet build

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
