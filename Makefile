CC ?= cc
CFLAGS ?= -std=c11 -O2 -Wall -Wextra -Wpedantic

all: replacement

replacement: src/replacement.c
	$(CC) $(CFLAGS) src/replacement.c -o replacement

traces: replacement
	sh scripts/run_required.sh

test: replacement
	sh tests/run_tests.sh

clean:
	rm -f replacement

.PHONY: all traces test clean
