# Any copyright is dedicated to the Public Domain.
# http://creativecommons.org/publicdomain/zero/1.0/
# Written by Nils Maier and modified by TheMoonThatRises

# This make file will:
#  - Download a set of dependencies and verify the known-good hashes.
#  - Build static libraries of aria2 dependencies.
#  - Create a statically linked aria2 library.
#    - The build will have all major features enabled, and will use
#      AppleTLS and GMP.
#
# This Makefile will also run all `make check` targets.
#
# The dependencies currently build are:
#  - zlib (compression, in particular web compression)
#  - c-ares (asynchronous DNS resolver)
#  - expat (XML parser, for metalinks)
#  - gmp (multi-precision arithmetric library, for DHKeyExchange, BitTorrent)
#  - sqlite3 (self-contained SQL database, for Firefox3 cookie reading)
#  - cppunit (unit tests for C++, framework in use by aria2 `make check`)
#
# In order to use this Makefile to build for Apple silicon, first install
# Command Line Tools:
#  - $ xcode-select --install
# 
# Then install dependencies with Homebrew:
#  - $ brew install automake
#  - $ brew install autoconf
#  - $ brew install libtool
#  - $ brew install pkg-config
#  - $ brew install docutils
#  - $ brew install libxml2
#  - $ brew install gsed
#
# Configure (differs from what's on the README to import pkg-config macros):
#  - $ autoreconf -i -I /opt/homebrew/share/aclocal/
#
# To use this Makefile, do something along the lines of
#  - $ mkdir build-release
#  - $ cd build-release
#  - $ ln -s ../makerelease-os.mk Makefile
#  - $ make -j
#
# Note: In theory, everything can be build in parallel, however the sub-makes
# will be called with an appropriate -j flag. Building the `deps` target in
# parallel before a general make might be beneficial, as the dependencies
# usually bottle-neck on the configure steps.
#
# Note: Of course, you need to have XCode with the command line tools
# installed for this to work, aka. a working compiler...
#
# Note: We're locally building the dependencies here, static libraries only.
# This is required, because when using brew or MacPorts, which also provide
# dynamic libraries, the linker will pick up the dynamic versions, always,
# with no way to instruct the linker otherwise.
# If you're building aria2 just for yourself and your system, using brewed
# libraries is fine as well.
#
# Note: This Makefile is riddled with mac-isms. It will not work on *nix.
#
# Note: The convoluted way to create separate arch builds and later merge them
# with lipo is because of two things:
#  1) Avoid patching c-ares, which hardcodes some sizes in its headers.
#
# Note: GTEST_FILTER is for c-ares as LiveSearchAny is problematic for some ISP and internet configurations

export GTEST_FILTER=-*LiveSearchANY*

SHELL := bash

# A bit awkward, but OSX doesn't have a proper `readlink -f`.
SRCDIR := $(shell dirname $(lastword $(shell stat -f "%N %Y" $(lastword $(MAKEFILE_LIST)))))

# Same as in script-helper, but a bit easier on the eye (but more error prone)
# and Makefile compatible
BASE_VERSION := $(shell grep AC_INIT $(SRCDIR)/configure.ac | cut -d'[' -f3 | cut -d']' -f1)

VERSION := $(BASE_VERSION)

# Set up compiler.
CC = cc
export CC
CXX = c++ -stdlib=libc++
export CXX

# Set up compiler/linker flags.
PLATFORMFLAGS ?= -mmacosx-version-min=12
OPTFLAGS ?= -Os
CFLAGS ?= $(PLATFORMFLAGS) $(OPTFLAGS)
export CFLAGS
CXXFLAGS ?= $(PLATFORMFLAGS) $(OPTFLAGS)
export CXXFLAGS
LDFLAGS ?= -Wl,-dead_strip
export LDFLAGS

LTO_FLAGS = -flto -ffunction-sections -fdata-sections

# Dependency versions
zlib_version = 1.3
zlib_hash = ff0ba4c292013dbc27530b3a81e1f9a813cd39de01ca5e0f8bf355702efa593e
zlib_url = http://zlib.net/zlib-$(zlib_version).tar.gz

expat_version = 2.5.0
expat_hash = 6b902ab103843592be5e99504f846ec109c1abb692e85347587f237a4ffa1033
expat_url = https://github.com/libexpat/libexpat/releases/download/R_2_5_0/expat-2.5.0.tar.gz
expat_cflags=$(CFLAGS) $(LTO_FLAGS)
expat_ldflags=$(CFLAGS) $(LTO_FLAGS)

cares_version = 1.19.1
cares_hash = 321700399b72ed0e037d0074c629e7741f6b2ec2dda92956abe3e9671d3e268e
cares_url = https://github.com/c-ares/c-ares/releases/download/cares-1_19_1/c-ares-$(cares_version).tar.gz
cares_confflags = "--enable-optimize=$(OPTFLAGS)"
cares_cflags=$(CFLAGS) $(LTO_FLAGS)
cares_ldflags=$(CFLAGS) $(LTO_FLAGS)

sqlite_version = autoconf-3430100
sqlite_hash = 39116c94e76630f22d54cd82c3cea308565f1715f716d1b2527f1c9c969ba4d9
sqlite_url = https://sqlite.org/2023/sqlite-$(sqlite_version).tar.gz
sqlite_cflags=$(CFLAGS) $(LTO_FLAGS)
sqlite_ldflags=$(CFLAGS) $(LTO_FLAGS)

gmp_version = 6.3.0
gmp_hash = a3c2b80201b89e68616f4ad30bc66aee4927c3ce50e33929ca819d5c43538898
gmp_url = https://gmplib.org/download/gmp/gmp-$(gmp_version).tar.xz
gmp_confflags = --disable-cxx --enable-assembly --with-pic --enable-fat
gmp_cflags=$(CFLAGS)
gmp_cxxflags=$(CXXFLAGS)

libgpgerror_version = 1.36
libgpgerror_hash = babd98437208c163175c29453f8681094bcaf92968a15cafb1a276076b33c97c
libgpgerror_url = https://gnupg.org/ftp/gcrypt/libgpg-error/libgpg-error-$(libgpgerror_version).tar.bz2
libgpgerror_cflags=$(CFLAGS) $(LTO_FLAGS)
libgpgerror_ldflags=$(CFLAGS) $(LTO_FLAGS)
libgpgerror_confflags = --with-pic --disable-languages --disable-doc --disable-nls

libgcrypt_version = 1.8.5
libgcrypt_hash = 3b4a2a94cb637eff5bdebbcaf46f4d95c4f25206f459809339cdada0eb577ac3
libgcrypt_url = https://gnupg.org/ftp/gcrypt/libgcrypt/libgcrypt-$(libgcrypt_version).tar.bz2
libgcrypt_confflags=--with-gpg-error-prefix=$(PWD)/arch --disable-O-flag-munging --disable-asm --disable-amd64-as-feature-detection
libgcrypt_cflags=$(PLATFORMFLAGS)
libgcrypt_cxxflags=$(PLATFORMFLAGS)

libssh2_version = 1.11.0
libssh2_hash = 3736161e41e2693324deb38c26cfdc3efe6209d634ba4258db1cecff6a5ad461
libssh2_url = https://www.libssh2.org/download/libssh2-$(libssh2_version).tar.gz
libssh2_cflags=$(CFLAGS) $(LTO_FLAGS)
libssh2_cxxflags=$(CXXFLAGS) $(LTO_FLAGS)
libssh2_ldflags=$(CFLAGS) $(LTO_FLAGS)
libssh2_confflags = --with-pic --without-openssl --with-libgcrypt=$(PWD)/arch --with-libgcrypt-prefix=$(PWD)/arch
libssh2_nocheck = yes

cppunit_version = 1.15.1
cppunit_hash = 89c5c6665337f56fd2db36bc3805a5619709d51fb136e51937072f63fcc717a7
cppunit_url = http://dev-www.libreoffice.org/src/cppunit-$(cppunit_version).tar.gz
cppunit_cflags=$(CFLAGS) $(LTO_FLAGS)
cppunit_cxxflags=$(CXXFLAGS) $(LTO_FLAGS)


# ARCHLIBS that can be template build
ARCHLIBS = expat cares sqlite gmp libgpgerror libgcrypt libssh2 cppunit
# NONARCHLIBS that cannot be template build
NONARCHLIBS = zlib

# Aria2 setup
ARIA2 := aria2-$(VERSION)
ARIA2_PREFIX := $(PWD)/$(ARIA2)
ARIA2_CONFFLAGS = \
        --enable-static \
				--enable-libaria2 \
        --disable-shared \
        --enable-metalink \
        --enable-bittorrent \
        --disable-nls \
        --with-appletls \
        --with-libgmp \
        --with-sqlite3 \
        --with-libz \
        --with-libexpat \
        --with-libcares \
        --with-libgcrypt \
        --with-libssh2 \
        --without-libuv \
        --without-gnutls \
        --without-openssl \
        --without-libnettle \
        --without-libxml2 \
        ARIA2_STATIC=yes

# Detect numer of CPUs to be used with make -j
CPUS = $(shell sysctl hw.ncpu | cut -d" " -f2)


# default target
all::

deps::


# All those .PRECIOUS files, because otherwise gmake will treat them as
# intermediates and remove them when the build completes. Thanks gmake!
.PRECIOUS: %.tar.gz
%.tar.gz:
	curl -o $@ -A 'curl/0; like wget' -L \
		$($(basename $(basename $@))_url)

.PRECIOUS: %.check
%.check: %.tar.gz
	@if test "$$(shasum -a256 $< | awk '{print $$1}')" != "$($(basename $@)_hash)"; then \
		echo "Invalid $@ hash"; \
		rm -f $<; \
		exit 1; \
	fi;
	touch $@

.PRECIOUS: %.stamp
%.stamp: %.tar.gz %.check
	tar xf $<
	mv $(basename $@)-$($(basename $@)_version) $(basename $@)
	touch $@

.PRECIOUS: cares.stamp
cares.stamp: cares.tar.gz cares.check
	tar xf $<
	mv c-ares-$($(basename $@)_version) $(basename $@)
	touch $@

.PRECIOUS: libgpgerror.stamp
libgpgerror.stamp: libgpgerror.tar.gz libgpgerror.check
	tar xf $<
	mv libgpg-error-$($(basename $@)_version) $(basename $@)
	touch $@

# Using (NON)ARCH_template kinda stinks, but real multi-target pattern rules
# only exist in feverish dreams.
define NONARCH_template
$(1).build: $(1).arm64.build

deps:: $(1).build

endef

.PRECIOUS: zlib.%.build
zlib.%.build: zlib.stamp
	$(eval BASE := $(basename $<))
	$(eval DEST := $(basename $@))
	$(eval ARCH := $(subst .,,$(suffix $(DEST))))
	rsync -a $(BASE)/ $(DEST)
	( cd $(DEST) && ./configure \
		--static --prefix=$(PWD)/arch \
		)
	$(MAKE) -C $(DEST) -sj$(CPUS) CFLAGS="$(CFLAGS) $(LTO_FLAGS) -arch $(ARCH)"
	$(MAKE) -C $(DEST) -sj$(CPUS) CFLAGS="$(CFLAGS) $(LTO_FLAGS) -arch $(ARCH)" check
	$(MAKE) -C $(DEST) -s install
	touch $@

$(foreach lib,$(NONARCHLIBS),$(eval $(call NONARCH_template,$(lib))))

define ARCH_template
.PRECIOUS: $(1).%.build
$(1).%.build: $(1).stamp
	$$(eval DEST := $$(basename $$@))
	$$(eval ARCH := $$(subst .,,$$(suffix $$(DEST))))
	mkdir -p $$(DEST)
	( cd $$(DEST) && ../$(1)/configure \
		--enable-static --disable-shared \
		--prefix=$(PWD)/arch \
		$$($(1)_confflags) \
		CFLAGS="$$($(1)_cflags) -arch $$(ARCH)" \
		CXXFLAGS="$$($(1)_cxxflags) -arch $$(ARCH) -std=c++11" \
		LDFLAGS="$(LDFLAGS) $$($(1)_ldflags)" \
		PKG_CONFIG_PATH=$$(PWD)/arch/lib/pkgconfig \
		)
	$$(MAKE) -C $$(DEST) -sj$(CPUS)
	if test -z '$$($(1)_nocheck)'; then $$(MAKE) -C $$(DEST) -sj$(CPUS) check; fi
	$$(MAKE) -C $$(DEST) -s install
	touch $$@

$(1).build: $(1).arm64.build

deps:: $(1).build

endef

$(foreach lib,$(ARCHLIBS),$(eval $(call ARCH_template,$(lib))))

.PRECIOUS: aria2.%.build
aria2.%.build: zlib.%.build expat.%.build gmp.%.build cares.%.build sqlite.%.build libgpgerror.%.build libgcrypt.%.build libssh2.%.build cppunit.%.build
	$(eval DEST := $$(basename $$@))
	$(eval ARCH := $$(subst .,,$$(suffix $$(DEST))))
	mkdir -p $(DEST)
	( cd $(DEST) && ../$(SRCDIR)/configure \
		--prefix=$(ARIA2_PREFIX) \
		--bindir=$(PWD)/$(DEST) \
		--sysconfdir=/etc \
		--with-cppunit-prefix=$(PWD)/arch \
		$(ARIA2_CONFFLAGS) \
		CFLAGS="$(CFLAGS) $(LTO_FLAGS) -arch $(ARCH) -I$(PWD)/arch/include" \
		CXXFLAGS="$(CXXFLAGS) $(LTO_FLAGS) -arch $(ARCH) -I$(PWD)/arch/include" \
		LDFLAGS="$(LDFLAGS) $(CXXFLAGS) $(LTO_FLAGS) -L$(PWD)/arch/lib" \
		PKG_CONFIG_PATH=$(PWD)/arch/lib/pkgconfig \
		)
	$(MAKE) -C $(DEST) -sj$(CPUS)
	$(MAKE) -C $(DEST) -sj$(CPUS) check
	# Check that the resulting executable is Position-independent (PIE)
	otool -hv $(DEST)/src/aria2c | grep -q PIE
	$(MAKE) -C $(DEST) -sj$(CPUS) install-strip
	touch $@

all:: aria2.arm64.build

clean:
	rm -rf *aria2*

cleaner: clean
	rm -rf *.build *.check *.stamp $(ARCHLIBS) $(NONARCHLIBS) arch *.arm64

really-clean: cleaner
	rm -rf *.tar.*


.PHONY: multi clean-dist clean cleaner really-clean
