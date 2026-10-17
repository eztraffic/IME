.PHONY: all build pkg notarize install uninstall status test clean

all: pkg

build:
	./Tools/package_ime.sh --build-only

pkg:
	./Tools/package_ime.sh --pkg

notarize:
	./Tools/package_ime.sh --notarize

install:
	./Tools/package_ime.sh --install

uninstall:
	@./Tools/uninstall.sh

# 診斷：列出安裝位置、LaunchServices 註冊路徑與 TIS 狀態
status:
	@echo "== 安裝位置"; ls -d "$$HOME/Library/Input Methods/HaoZhuyin.app" "/Library/Input Methods/HaoZhuyin.app" 2>/dev/null || true
	@echo "== LaunchServices 註冊路徑"; /System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -dump 2>/dev/null | sed -n 's/^path:[[:space:]]*\(.*HaoZhuyin\.app\) (0x[0-9a-f]*)$$/\1/p' | sort -u
	@echo "== TIS"; for a in "$$HOME/Library/Input Methods/HaoZhuyin.app" "/Library/Input Methods/HaoZhuyin.app"; do [ -x "$$a/Contents/MacOS/HaoZhuyin" ] && { "$$a/Contents/MacOS/HaoZhuyin" --status; break; }; done; true

test:
	DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test

clean:
	@/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -u build/HaoZhuyin.app 2>/dev/null || true
	rm -rf build dist .build
