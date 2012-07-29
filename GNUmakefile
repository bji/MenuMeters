
# Needed for space handling in paths
empty :=
space := $(empty) $(empty)
safedir = $(subst _GNU_MAKEFILE_SPACE_,$(space),$(dir $(subst $(space),_GNU_MAKEFILE_SPACE_,$1)))

CFLAGS :=

# These compiler and flags were determined by looking at the commands
# that Xcode runs for the Xcode MenuMeters project

# Build both i386 and x86_64 architecture objects
CFLAGS := $(CFLAGS) -arch x86_64 -arch i386

# The code requires some c99 features
CFLAGS := $(CFLAGS) -std=c99

# Optimizations
CFLAGS := $(CFLAGS) -O3

# Enable GC, required for Mac OS X 10.5 and later
CFLAGS := $(CFLAGS) -fobjc-gc

# I think some features that the code uses requires this
CFLAGS := $(CFLAGS) -mmacosx-version-min=10.5

# I guess we want all warnings
CFLAGS := $(CFLAGS) -Wall -Wshorten-64-to-32

# Private frameworks are used
# CFLAGS := $(CFLAGS) -F /System/Library/PrivateFrameworks

# Required include path
CFLAGS := $(CFLAGS) -ICommon

# Force include of a common header file
CFLAGS := $(CFLAGS) -include MenuMeters.pch

LINKFLAGS := 

LINKFLAGS := $(LINKFLAGS) -arch x86_64 -arch i386

LINKFLAGS := $(LINKFLAGS) -F /System/Library/PrivateFrameworks

.PHONY: all
all: installer

.PHONY: binaries
binaries: InstallTool MenuMeters MenuMeterCPU MenuMeterDisk MenuMeterMem \
          MenuMeterNet MenuMeterDefaults MenuMeters\ Installer

.PHONY: nibs
nibs: build/nib/Installer/Resources/English.lproj/Installer.nib \
      build/nib/Installer/Resources/French.lproj/Installer.nib \
      build/nib/Installer/Resources/German.lproj/Installer.nib \
      build/nib/Installer/Resources/Italian.lproj/Installer.nib \
      build/nib/Installer/Resources/Japanese.lproj/Installer.nib \
      build/nib/Installer/Resources/nl.lproj/Installer.nib \
      build/nib/Installer/Resources/zh_CN.lproj/Installer.nib \
      build/nib/PrefPane/English.lproj/MenuMetersPref.nib \
      build/nib/PrefPane/French.lproj/MenuMetersPref.nib \
      build/nib/PrefPane/German.lproj/MenuMetersPref.nib \
      build/nib/PrefPane/Italian.lproj/MenuMetersPref.nib \
      build/nib/PrefPane/Japanese.lproj/MenuMetersPref.nib \
      build/nib/PrefPane/nl.lproj/MenuMetersPref.nib \
      build/nib/PrefPane/zh_CN.lproj/MenuMetersPref.nib

build/obj/%.o: %.m
	@mkdir -p "$(call safedir,$@)"
	gcc $(CFLAGS) -c "$^" -o "$@"

build/nib/%.nib: %.nib
	@mkdir -p "$(call safedir,$@)"
	/usr/bin/ibtool --strip "$@" --output-format human-readable-text "$^"

.PHONY: InstallTool
InstallTool: build/bin/InstallTool
build/bin/InstallTool: build/obj/Installer/InstallTool.o
	@mkdir -p "$(call safedir,$@)"
	gcc $(LINKFLAGS) -o $@ $^ -framework Cocoa

.PHONY: MenuMeterDefaults
MenuMeterDefaults: build/bin/MenuMeterDefaults
build/bin/MenuMeterDefaults: build/obj/Common/MenuMeterDefaults.o
	@mkdir -p "$(call safedir,$@)"
	gcc -bundle $(LINKFLAGS) -o $@ $^ -framework Cocoa

.PHONY: MenuMeters
MenuMeters: build/bin/MenuMeters
build/bin/MenuMeters: build/obj/Common/MenuMeterDefaults.o \
                      build/obj/Common/MenuMeterPowerMate.o \
                      build/obj/PrefPane/MenuMetersPref.o
	@mkdir -p "$(call safedir,$@)"
	gcc -bundle $(LINKFLAGS) -o $@ $^ -framework Cocoa -framework IOKit -framework SystemConfiguration -framework PreferencePanes

.PHONY: MenuMeterCPU
MenuMeterCPU: build/bin/MenuMeterCPU
build/bin/MenuMeterCPU: build/obj/MenuExtras/MenuMeterCPU/MenuMeterCPUView.o \
                        build/obj/MenuExtras/MenuMeterCPU/MenuMeterCPUExtra.o \
                        build/obj/MenuExtras/MenuMeterCPU/MenuMeterCPUStats.o \
                        build/obj/MenuExtras/MenuMeterCPU/MenuMeterUptime.o \
                        build/obj/Common/MenuMeterPowerMate.o \
                        build/obj/Common/MenuMeterWorkarounds.o
	@mkdir -p "$(call safedir,$@)"
	gcc -bundle $(LINKFLAGS) -o $@ $^ -framework SystemUIPlugin -framework Cocoa -framework Carbon -framework IOKit

.PHONY: MenuMeterDisk
MenuMeterDisk: build/bin/MenuMeterDisk
build/bin/MenuMeterDisk: \
                      build/obj/MenuExtras/MenuMeterDisk/MenuMeterDiskView.o \
                      build/obj/MenuExtras/MenuMeterDisk/MenuMeterDiskExtra.o \
                      build/obj/MenuExtras/MenuMeterDisk/MenuMeterDiskIO.o \
                      build/obj/MenuExtras/MenuMeterDisk/MenuMeterDiskSpace.o
	@mkdir -p "$(call safedir,$@)"
	gcc -bundle $(LINKFLAGS) -o $@ $^ -framework SystemUIPlugin -framework Cocoa -framework Carbon -framework IOKit

.PHONY: MenuMeterNet
MenuMeterNet: build/bin/MenuMeterNet
build/bin/MenuMeterNet: build/obj/MenuExtras/MenuMeterNet/MenuMeterNetExtra.o \
                        build/obj/MenuExtras/MenuMeterNet/MenuMeterNetView.o \
                        build/obj/MenuExtras/MenuMeterNet/MenuMeterNetStats.o \
                        build/obj/MenuExtras/MenuMeterNet/MenuMeterNetConfig.o \
                        build/obj/MenuExtras/MenuMeterNet/MenuMeterNetPPP.o \
                        build/obj/Common/MenuMeterWorkarounds.o
	@mkdir -p "$(call safedir,$@)"
	gcc -bundle $(LINKFLAGS) -o $@ $^ -framework SystemUIPlugin -framework Cocoa -framework IOKit -framework SystemConfiguration

.PHONY: MenuMeterMem
MenuMeterMem: build/bin/MenuMeterMem
build/bin/MenuMeterMem: build/obj/MenuExtras/MenuMeterMem/MenuMeterMemView.o \
                        build/obj/MenuExtras/MenuMeterMem/MenuMeterMemExtra.o \
                        build/obj/MenuExtras/MenuMeterMem/MenuMeterMemStats.o \
                        build/obj/Common/MenuMeterWorkarounds.o
	@mkdir -p "$(call safedir,$@)"
	gcc -bundle $(LINKFLAGS) -o $@ $^ -framework SystemUIPlugin -framework Cocoa -framework Carbon

.PHONY: MenuMeters\ Installer
MenuMeters\ Installer: build/bin/MenuMeters\ Installer
build/bin/MenuMeters\ Installer: build/obj/Installer/InstallerApp.o \
                                 build/obj/Installer/InstallerAppMain.o
	@mkdir -p "$(dir $@)"
	gcc $(LINKFLAGS) -o "$@" $^ -framework Cocoa -framework Security

.PHONY: dmg
dmg: build/MenuMeters\ Installer.dmg
build/MenuMeters\ Installer.dmg: installer
	/usr/bin/hdiutil create -ov -srcfolder "build/MenuMeters Installer.app" -volname "MenuMeters 1.BJI" "build/MenuMeters"

.PHONY: clean
clean:
	rm -rf build

# Moved installer targets into a separate Makefile to make this file
# easier to read and deal with
include Installer.gmake
