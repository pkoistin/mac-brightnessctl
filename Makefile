CC = clang
CFLAGS = -Wall -Wextra -O2
LDFLAGS = -framework Foundation

COMMON_SRC = BrightnessControl.m KeyboardManager.m
HEADERS = BrightnessControl.h KeyboardBrightnessClient.h KeyboardManager.h

OUT = mac-brightnessctl
KBD_OUT = kbd-brightness-keys

all: $(OUT)

$(OUT): main.m $(COMMON_SRC) $(HEADERS)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ main.m $(COMMON_SRC)

$(KBD_OUT): kbd-brightness-keys.m $(COMMON_SRC) $(HEADERS)
	$(CC) $(CFLAGS) $(LDFLAGS) -framework AppKit -framework ApplicationServices -o $@ kbd-brightness-keys.m $(COMMON_SRC)

clean:
	rm -f $(OUT) $(KBD_OUT)

.PHONY: all clean
