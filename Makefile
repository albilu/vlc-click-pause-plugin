PROJECT := vlc-click-pause
VERSION := 0.1.0
PKG_CONFIG ?= pkg-config
CC ?= cc
CFLAGS ?= -O2 -g
CPPFLAGS ?=
LDFLAGS ?=
PREFIX ?= /usr
PLUGINDIR ?= $(shell $(PKG_CONFIG) --variable=pluginsdir vlc-plugin 2>/dev/null)
DOCDIR ?= $(PREFIX)/share/doc/vlc-plugin-clickpause
DESTDIR ?=

VLC_CFLAGS = $(shell $(PKG_CONFIG) --cflags vlc-plugin)
VLC_LIBS = $(shell $(PKG_CONFIG) --libs vlc-plugin)
# Support both layouts of the VLC 3.x object headers, including distro backports.
VLC_OBJECT_CFLAGS = $(shell printf '%s\n' '#include <vlc_common.h>' \
	'void *instance(vlc_object_t *o) { return o->obj.libvlc; }' | \
	$(CC) $(CPPFLAGS) $(VLC_CFLAGS) -std=gnu11 -x c -c -o /dev/null - \
	2>/dev/null && printf '%s' '-DHAVE_VLC_OBJECT_MEMBERS')
TARGET := build/libclickpause_plugin.so
DISTFILES := Makefile README.md LICENSE src packaging tests .gitignore

.PHONY: all check-sdk check check-installed install uninstall dist deb clean
all: $(TARGET)

check-sdk:
	@$(PKG_CONFIG) --exists 'vlc-plugin >= 3.0' 'vlc-plugin < 4.0' || \
		{ echo "VLC 3.x development files are required (Debian/Ubuntu: libvlccore-dev)." >&2; exit 1; }

$(TARGET): src/clickpause.c Makefile | check-sdk
	mkdir -p build
	$(CC) $(CPPFLAGS) $(CFLAGS) $(VLC_CFLAGS) $(VLC_OBJECT_CFLAGS) -std=gnu11 -Wall -Wextra \
		-fPIC -fvisibility=hidden -DMODULE_STRING='"clickpause"' \
		-shared $(LDFLAGS) -Wl,-z,defs -Wl,-z,relro,-z,now \
		-o $@ $< $(VLC_LIBS)

check: $(TARGET)
	python3 tests/smoke.py "$(abspath $(TARGET))"

check-installed:
	python3 tests/smoke.py --installed

install: $(TARGET)
	@test -n "$(PLUGINDIR)" || { echo "Set PLUGINDIR to VLC's plugin directory." >&2; exit 1; }
	install -Dm755 $(TARGET) "$(DESTDIR)$(PLUGINDIR)/video_filter/$(notdir $(TARGET))"
	install -Dm644 README.md "$(DESTDIR)$(DOCDIR)/README.md"
	install -Dm644 LICENSE "$(DESTDIR)$(DOCDIR)/copyright"

uninstall:
	@test -n "$(PLUGINDIR)" || { echo "Set PLUGINDIR to VLC's plugin directory." >&2; exit 1; }
	rm -f "$(DESTDIR)$(PLUGINDIR)/video_filter/$(notdir $(TARGET))"
	rm -f "$(DESTDIR)$(DOCDIR)/README.md" "$(DESTDIR)$(DOCDIR)/copyright"

dist:
	mkdir -p dist
	tar --exclude=__pycache__ --exclude='*.pyc' \
		--transform='s,^,$(PROJECT)-$(VERSION)/,' \
		-czf dist/$(PROJECT)-$(VERSION).tar.gz $(DISTFILES)

deb: $(TARGET)
	sh packaging/deb.sh "$(VERSION)" "$(abspath $(TARGET))" "$(PLUGINDIR)"

clean:
	rm -rf build dist
