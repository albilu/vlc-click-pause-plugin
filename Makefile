PROJECT := vlc-click-pause
VERSION := 0.2.0
PKG_CONFIG ?= pkg-config
CC ?= cc
PYTHON ?= python3
MSGFMT ?= msgfmt
XGETTEXT ?= xgettext
UI_LANGUAGE ?= en
LANGUAGES := en $(patsubst po/%.po,%,$(wildcard po/*.po))
ifeq ($(filter $(UI_LANGUAGE),$(LANGUAGES)),)
$(error Unsupported UI_LANGUAGE '$(UI_LANGUAGE)'; choose one of: $(LANGUAGES))
endif
PACKAGE := vlc-plugin-clickpause$(if $(filter-out en,$(UI_LANGUAGE)),-$(UI_LANGUAGE))
CFLAGS ?= -O2 -g
CPPFLAGS ?=
LDFLAGS ?=
PREFIX ?= /usr
PLUGINDIR ?= $(shell $(PKG_CONFIG) --variable=pluginsdir vlc-plugin 2>/dev/null)
DOCDIR ?= $(PREFIX)/share/doc/$(PACKAGE)
DESTDIR ?=

VLC_CFLAGS = $(shell $(PKG_CONFIG) --cflags vlc-plugin)
VLC_LIBS = $(shell $(PKG_CONFIG) --libs vlc-plugin)
# Support both layouts of the VLC 3.x object headers, including distro backports.
VLC_OBJECT_CFLAGS = $(shell printf '%s\n' '#include <vlc_common.h>' \
	'void *instance(vlc_object_t *o) { return o->obj.libvlc; }' | \
	$(CC) $(CPPFLAGS) $(VLC_CFLAGS) -std=gnu11 -x c -c -o /dev/null - \
	2>/dev/null && printf '%s' '-DHAVE_VLC_OBJECT_MEMBERS')
BUILDDIR := build/$(UI_LANGUAGE)
TARGET := $(BUILDDIR)/libclickpause_plugin.so
CATALOG := $(if $(filter-out en,$(UI_LANGUAGE)),$(BUILDDIR)/clickpause.mo)
I18N_HEADER := $(BUILDDIR)/i18n.h
DISTFILES := Makefile README.md LICENSE src packaging tests tools po .gitignore

.PHONY: all check-sdk check check-installed pot install uninstall dist deb clean
all: $(TARGET)

check-sdk:
	@$(PKG_CONFIG) --exists 'vlc-plugin >= 3.0' 'vlc-plugin < 4.0' || \
		{ echo "VLC 3.x development files are required (Debian/Ubuntu: libvlccore-dev)." >&2; exit 1; }

$(BUILDDIR)/clickpause.mo: po/$(UI_LANGUAGE).po
	mkdir -p $(BUILDDIR)
	$(MSGFMT) --check --check-format -o $@ $<

$(I18N_HEADER): tools/compile_translations.py Makefile $(CATALOG)
	mkdir -p $(BUILDDIR)
	$(PYTHON) tools/compile_translations.py $(if $(CATALOG),--catalog "$(CATALOG)") --output $@

$(TARGET): src/clickpause.c $(I18N_HEADER) Makefile | check-sdk
	mkdir -p $(BUILDDIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) $(VLC_CFLAGS) $(VLC_OBJECT_CFLAGS) -std=gnu11 -Wall -Wextra \
		-I$(BUILDDIR) -fPIC -fvisibility=hidden -DMODULE_STRING='"clickpause"' \
		-shared $(LDFLAGS) -Wl,-z,defs -Wl,-z,relro,-z,now \
		-o $@ $< $(VLC_LIBS)

check: $(TARGET)
	$(PYTHON) tests/smoke.py --language $(UI_LANGUAGE) "$(abspath $(TARGET))"

check-installed:
	$(PYTHON) tests/smoke.py --language $(UI_LANGUAGE) --installed

pot:
	$(XGETTEXT) --language=C --keyword=_ --from-code=UTF-8 \
		--package-name=$(PROJECT) --package-version=$(VERSION) \
		--copyright-holder='VLC click-pause contributors' \
		-o po/$(PROJECT).pot src/clickpause.c

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
	sh packaging/deb.sh "$(VERSION)" "$(abspath $(TARGET))" "$(PLUGINDIR)" "$(UI_LANGUAGE)"

clean:
	rm -rf build dist
