.PHONY: all dylib check
all: dylib
dylib:
	bash scripts/build-ios.sh
check:
	XAD_DIAGNOSTICS=0 XAD_OUTPUT_DIR=build/no-diagnostics bash scripts/build-ios.sh
