# Build the modernized APLINKS server (POSIX: Linux / macOS).
# On Windows use build.ps1 (or: gcc -x c -std=c99 -O2 -o aplinks32.exe APLINKS.C).

CC     ?= cc
CFLAGS ?= -std=c99 -O2 -Wall -Wextra

aplinks: APLINKS.C
	$(CC) $(CFLAGS) -o aplinks APLINKS.C

clean:
	rm -f aplinks

.PHONY: clean
