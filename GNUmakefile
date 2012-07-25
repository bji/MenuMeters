
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

OBJECTS := obj/Common/MenuMeterDefaults.o \
           obj/Common/MenuMeterPowerMate.o \
           obj/PrefPane/MenuMetersPref.o

.PHONY: all
all: bin/InstallTool bin/MenuMeters bin/MenuMeterCPU bin/MenuMeterDisk \
     bin/MenuMeterMem bin/MenuMeterNet bin/MenuMeterDefaults \
     bin/MenuMeters_Installer

obj/%.o: %.m
	@mkdir -p $(dir $@)
	gcc $(CFLAGS) -c $^ -o $@

bin/InstallTool: obj/Installer/InstallTool.o
	@mkdir -p $(dir $@)
	gcc $(LINKFLAGS) -o $@ $^ -framework Cocoa

bin/MenuMeterDefaults: obj/Common/MenuMeterDefaults.o
	@mkdir -p $(dir $@)
	gcc -bundle $(LINKFLAGS) -o $@ $^ -framework Cocoa

bin/MenuMeters: obj/Common/MenuMeterDefaults.o \
                obj/Common/MenuMeterPowerMate.o \
                obj/PrefPane/MenuMetersPref.o
	@mkdir -p $(dir $@)
	gcc -bundle $(LINKFLAGS) -o $@ $^ -framework Cocoa -framework IOKit -framework SystemConfiguration -framework PreferencePanes

bin/MenuMeterCPU: obj/MenuExtras/MenuMeterCPU/MenuMeterCPUView.o \
                  obj/MenuExtras/MenuMeterCPU/MenuMeterCPUExtra.o \
                  obj/MenuExtras/MenuMeterCPU/MenuMeterCPUStats.o \
                  obj/MenuExtras/MenuMeterCPU/MenuMeterUptime.o \
                  obj/Common/MenuMeterPowerMate.o \
                  obj/Common/MenuMeterWorkarounds.o
	@mkdir -p $(dir $@)
	gcc -bundle $(LINKFLAGS) -o $@ $^ -framework SystemUIPlugin -framework Cocoa -framework Carbon -framework IOKit

bin/MenuMeterDisk: obj/MenuExtras/MenuMeterDisk/MenuMeterDiskView.o \
                   obj/MenuExtras/MenuMeterDisk/MenuMeterDiskExtra.o \
                   obj/MenuExtras/MenuMeterDisk/MenuMeterDiskIO.o \
                   obj/MenuExtras/MenuMeterDisk/MenuMeterDiskSpace.o
	@mkdir -p $(dir $@)
	gcc -bundle $(LINKFLAGS) -o $@ $^ -framework SystemUIPlugin -framework Cocoa -framework Carbon -framework IOKit

bin/MenuMeterNet: obj/MenuExtras/MenuMeterNet/MenuMeterNetExtra.o \
                  obj/MenuExtras/MenuMeterNet/MenuMeterNetView.o \
                  obj/MenuExtras/MenuMeterNet/MenuMeterNetStats.o \
                  obj/MenuExtras/MenuMeterNet/MenuMeterNetConfig.o \
                  obj/MenuExtras/MenuMeterNet/MenuMeterNetPPP.o \
                  obj/Common/MenuMeterWorkarounds.o
	@mkdir -p $(dir $@)
	gcc -bundle $(LINKFLAGS) -o $@ $^ -framework SystemUIPlugin -framework Cocoa -framework IOKit -framework SystemConfiguration

bin/MenuMeterMem: obj/MenuExtras/MenuMeterMem/MenuMeterMemView.o \
                  obj/MenuExtras/MenuMeterMem/MenuMeterMemExtra.o \
                  obj/MenuExtras/MenuMeterMem/MenuMeterMemStats.o \
                  obj/Common/MenuMeterWorkarounds.o
	@mkdir -p $(dir $@)
	gcc -bundle $(LINKFLAGS) -o $@ $^ -framework SystemUIPlugin -framework Cocoa -framework Carbon

bin/MenuMeters_Installer: obj/Installer/InstallerApp.o \
                          obj/Installer/InstallerAppMain.o
	@mkdir -p $(dir $@)
	gcc $(LINKFLAGS) -o $@ $^ -framework Cocoa -framework Security

.PHONY: clean
clean:
	rm -rf obj bin
