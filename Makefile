.PHONY: all dylib check
all: dylib
dylib:
	bash scripts/build-ios.sh
check: dylib
