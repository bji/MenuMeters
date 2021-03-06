//
//  MenuMeterCPUStats.m
//
// 	Reader object for CPU information and load
//
//	Copyright (c) 2002-2012 Alex Harper
//
// 	This file is part of MenuMeters.
//
// 	MenuMeters is free software; you can redistribute it and/or modify
// 	it under the terms of the GNU General Public License version 2 as
//  published by the Free Software Foundation.
//
// 	MenuMeters is distributed in the hope that it will be useful,
// 	but WITHOUT ANY WARRANTY; without even the implied warranty of
// 	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// 	GNU General Public License for more details.
//
// 	You should have received a copy of the GNU General Public License
// 	along with MenuMeters; if not, write to the Free Software
// 	Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
//

#import "MenuMeterCPUStats.h"


///////////////////////////////////////////////////////////////
//
//	Private methods
//
///////////////////////////////////////////////////////////////

@interface MenuMeterCPUStats (PrivateMethods)
uint32_t cpuCount;
- (NSString *)cpuPrettyName;
@end


///////////////////////////////////////////////////////////////
//
//	Localized strings
//
///////////////////////////////////////////////////////////////

#define kProcessorNameFormat				@"%u %@ @ %@"
#define kTaskThreadFormat					@"%d tasks, %d threads"
#define kLoadAverageFormat					@"%@, %@, %@"
#define kNoInfoErrorMessage					@"No info available"


///////////////////////////////////////////////////////////////
//
//	init/dealloc
//
///////////////////////////////////////////////////////////////

@implementation MenuMeterCPUStats

- (id)init {

	// Allow super to init
	self = [super init];
	if (!self) {
		return nil;
	}

	// Gather the pretty name
	cpuName = [[self cpuPrettyName] retain];
	if (!cpuName) {
		[self release];
		return nil;
	}

	// Set up a NumberFormatter for localization. This is based on code contributed by Mike Fischer
	// (mike.fischer at fi-works.de) for use in MenuMeters.
	// We have to do this early so we can use the resulting format on the GHz processor string
	NSNumberFormatter *tempFormatter = [[[NSNumberFormatter alloc] init] autorelease];
	[tempFormatter setLocalizesFormat:YES];
	[tempFormatter setFormat:@"0.00"];
	// Go through an archive/unarchive cycle to work around a bug on pre-10.2.2 systems
	// see http://cocoa.mamasam.com/COCOADEV/2001/12/2/21029.php
	twoDigitFloatFormatter = [[NSUnarchiver unarchiveObjectWithData:[NSArchiver archivedDataWithRootObject:tempFormatter]] retain];
	if (!twoDigitFloatFormatter) {
		[self release];
		return nil;
	}

	// Gather the clock rate string
	uint32_t clockRate = 0;
	int mib[2] = { CTL_HW, HW_CPU_FREQ };
	size_t sysctlLength = sizeof(clockRate);
	if (sysctl(mib, 2, &clockRate, &sysctlLength, NULL, 0)) {
		[self release];
		return nil;
	}
	if (clockRate > 1000000000) {
		clockSpeed = [[NSString stringWithFormat:@"%@GHz",
							[twoDigitFloatFormatter stringForObjectValue:
								[NSNumber numberWithFloat:(float)clockRate / 1000000000]]] retain];
	}
	else {
		clockSpeed = [[NSString stringWithFormat:@"%dMHz", clockRate / 1000000] retain];
	}
	if (!clockSpeed) {
		[self release];
		return nil;
	}

	// Gather the cpu count
	sysctlLength = sizeof(cpuCount);
	mib[0] = CTL_HW;
	mib[1] = HW_NCPU;
	if (sysctl(mib, 2, &cpuCount, &sysctlLength, NULL, 0)) {
		[self release];
		return nil;
	}

	// Set up our mach host and default processor set for later calls
	machHost = mach_host_self();
	processor_set_default(machHost, &processorSet);

	// Build the storage for the prior ticks and store the first block of data
	natural_t processorCount;
	processor_cpu_load_info_t processorTickInfo;
	mach_msg_type_number_t processorInfoCount;
	kern_return_t err = host_processor_info(machHost, PROCESSOR_CPU_LOAD_INFO, &processorCount,
											(processor_info_array_t *)&processorTickInfo, &processorInfoCount);
	if (err != KERN_SUCCESS) {
		[self release];
		return nil;
	}
	priorCPUTicks = malloc(processorCount * sizeof(struct processor_cpu_load_info));
	for (natural_t i = 0; i < processorCount; i++) {
		for (natural_t j = 0; j < CPU_STATE_MAX; j++) {
			priorCPUTicks[i].cpu_ticks[j] = processorTickInfo[i].cpu_ticks[j];
		}
	}
	vm_deallocate(mach_task_self(), (vm_address_t)processorTickInfo, (vm_size_t)(processorInfoCount * sizeof(natural_t)));

	// Localizable strings load
	localizedStrings = [[NSDictionary dictionaryWithObjectsAndKeys:
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kProcessorNameFormat value:nil table:nil],
							kProcessorNameFormat,
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kTaskThreadFormat value:nil table:nil],
							kTaskThreadFormat,
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kLoadAverageFormat value:nil table:nil],
							kLoadAverageFormat,
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kNoInfoErrorMessage value:nil table:nil],
							kNoInfoErrorMessage,
							nil] retain];
	if (!localizedStrings) {
		[self release];
		return nil;
	}

	// Send on back
	return self;

} // init

- (void)dealloc {

	[cpuName release];
	[clockSpeed release];
	if (priorCPUTicks) free(priorCPUTicks);
	[localizedStrings release];
	[twoDigitFloatFormatter release];
	[super dealloc];

} // dealloc

///////////////////////////////////////////////////////////////
//
//	CPU info
//
///////////////////////////////////////////////////////////////

- (NSString *)cpuName {

	return cpuName;

} // cpuName

- (NSString *)cpuSpeed {

	return clockSpeed;

} // cpuSpeed

- (uint32_t)numberOfCPUs:(BOOL)combineLowerHalf {

	return combineLowerHalf ? (cpuCount / 2) + 1 : cpuCount;

} // numberOfCPUs

- (NSString *)processorDescription {

	return [NSString stringWithFormat:[localizedStrings objectForKey:kProcessorNameFormat],
                   [self numberOfCPUs:NO], [self cpuName], [self cpuSpeed]];

} // processorDescription

///////////////////////////////////////////////////////////////
//
//	Load info
//
///////////////////////////////////////////////////////////////

- (NSString *)currentProcessorTasks {

	struct processor_set_load_info loadInfo;
	mach_msg_type_number_t count = PROCESSOR_SET_LOAD_INFO_COUNT;
	kern_return_t err = processor_set_statistics(processorSet, PROCESSOR_SET_LOAD_INFO,
												 (processor_set_info_t)&loadInfo, &count);
	if (err != KERN_SUCCESS) {
		return [localizedStrings objectForKey:kNoInfoErrorMessage];
	} else {
		return [NSString stringWithFormat:[localizedStrings objectForKey:kTaskThreadFormat],
					loadInfo.task_count, loadInfo.thread_count];
	}

} // currentProcessorTasks

- (NSString *)loadAverage {

	// Fetch using getloadavg() to better match top, from Michael Nordmeyer (http://goodyworks.com)
	double loads[3] = { 0, 0, 0 };
	if (getloadavg(loads, 3) != 3) {
		return [localizedStrings objectForKey:kNoInfoErrorMessage];
	} else {
		return [NSString stringWithFormat:[localizedStrings objectForKey:kLoadAverageFormat],
					[twoDigitFloatFormatter stringForObjectValue:[NSNumber numberWithFloat:(float)loads[0]]],
					[twoDigitFloatFormatter stringForObjectValue:[NSNumber numberWithFloat:(float)loads[1]]],
					[twoDigitFloatFormatter stringForObjectValue:[NSNumber numberWithFloat:(float)loads[2]]]];
	}

} // loadAverage

- (NSArray *)currentLoad: (BOOL)sorted andCombineLowerHalf:(BOOL)combine {

	// Read the current ticks
	natural_t processorCount;
	processor_cpu_load_info_t processorTickInfo;
	mach_msg_type_number_t processorInfoCount;
	kern_return_t err = host_processor_info(machHost, PROCESSOR_CPU_LOAD_INFO, &processorCount,
											(processor_info_array_t *)&processorTickInfo, &processorInfoCount);
	if (err != KERN_SUCCESS) return nil;

	// We have valid info so build return array

    // First, build parallel arrays of user and system load values
    NSMutableArray *loadUser = [NSMutableArray array];
    NSMutableArray *loadSystem = [NSMutableArray array];

	for (natural_t i = 0; i < processorCount; i++) {

		// Calc load types and totals, with guards against 32-bit overflow
		// (values are natural_t)
		uint64_t system = 0, user = 0, idle = 0, total = 0;

		if (processorTickInfo[i].cpu_ticks[CPU_STATE_SYSTEM] >= priorCPUTicks[i].cpu_ticks[CPU_STATE_SYSTEM]) {
			system = processorTickInfo[i].cpu_ticks[CPU_STATE_SYSTEM] - priorCPUTicks[i].cpu_ticks[CPU_STATE_SYSTEM];
		} else {
			system = processorTickInfo[i].cpu_ticks[CPU_STATE_SYSTEM] + (UINT_MAX - priorCPUTicks[i].cpu_ticks[CPU_STATE_SYSTEM] + 1);
		}
		if (processorTickInfo[i].cpu_ticks[CPU_STATE_USER] >= priorCPUTicks[i].cpu_ticks[CPU_STATE_USER]) {
			user = processorTickInfo[i].cpu_ticks[CPU_STATE_USER] - priorCPUTicks[i].cpu_ticks[CPU_STATE_USER];
		} else {
			user = processorTickInfo[i].cpu_ticks[CPU_STATE_USER] + (ULONG_MAX - priorCPUTicks[i].cpu_ticks[CPU_STATE_USER] + 1);
		}
		// Count nice as user (nice slot non-zero only on  OS versions prior to 10.4)
		// Radar 5644966, duplicate 5555821. Apple says its intentional, so stop
		// pretending its going to get fixed.
		if (processorTickInfo[i].cpu_ticks[CPU_STATE_NICE] >= priorCPUTicks[i].cpu_ticks[CPU_STATE_NICE]) {
			user += processorTickInfo[i].cpu_ticks[CPU_STATE_NICE] - priorCPUTicks[i].cpu_ticks[CPU_STATE_NICE];
		} else {
			user += processorTickInfo[i].cpu_ticks[CPU_STATE_NICE] + (ULONG_MAX - priorCPUTicks[i].cpu_ticks[CPU_STATE_NICE] + 1);
		}
		if (processorTickInfo[i].cpu_ticks[CPU_STATE_IDLE] >= priorCPUTicks[i].cpu_ticks[CPU_STATE_IDLE]) {
			idle = processorTickInfo[i].cpu_ticks[CPU_STATE_IDLE] - priorCPUTicks[i].cpu_ticks[CPU_STATE_IDLE];
		} else {
			idle = processorTickInfo[i].cpu_ticks[CPU_STATE_IDLE] + (ULONG_MAX - priorCPUTicks[i].cpu_ticks[CPU_STATE_IDLE] + 1);
		}
		total = system + user + idle;

		// Sanity
		if (total < 1) {
			total = 1;
		}

        [loadUser addObject:[NSNumber numberWithFloat:((float)user / (float)total)]];
        [loadSystem addObject:[NSNumber numberWithFloat:((float)system / (float)total)]];
	}

	// Copy the new data into previous
	for (natural_t i = 0; i < processorCount; i++) {
		for (natural_t j = 0; j < CPU_STATE_MAX; j++) {
			priorCPUTicks[i].cpu_ticks[j] = processorTickInfo[i].cpu_ticks[j];
		}
	}

    // Sort the load if necessary
    if (sorted == YES) {
        NSMutableArray *sortedUser = [NSMutableArray array];
        NSMutableArray *sortedSystem = [NSMutableArray array];
        
        for (natural_t i = 0; i < processorCount; i++) {
            float maxSum = 0.0f;
            natural_t maxIndex = 0;
            for (natural_t j = 0; j < (processorCount - i); j++) {
                float sum = [[loadUser objectAtIndex: j] floatValue] + [[loadSystem objectAtIndex: j] floatValue];
                if (sum > maxSum) {
                    maxSum = sum;
                    maxIndex = j;
                }
            }
            [sortedUser addObject: [loadUser objectAtIndex: maxIndex]];
            [sortedSystem addObject: [loadSystem objectAtIndex: maxIndex]];
            [loadUser removeObjectAtIndex: maxIndex];
            [loadSystem removeObjectAtIndex: maxIndex];
        }

        loadUser = sortedUser;
        loadSystem = sortedSystem;

        // Now reduce the least-utilized half of the CPUs into a single value
        // if requested to do so.
        if (combine) {
            processorCount /= 2;
            NSMutableArray *combinedUser = [NSMutableArray array];
            NSMutableArray *combinedSystem = [NSMutableArray array];
            for (natural_t i = 0; i < processorCount; i++) {
                [combinedUser addObject: [loadUser objectAtIndex: i]];
                [combinedSystem addObject: [loadSystem objectAtIndex: i]];
            }
            float system = 0, user = 0;
            for (natural_t i = 0; i < processorCount; i++) {
                natural_t loadIndex = processorCount + i;
                user += [[loadUser objectAtIndex: loadIndex] floatValue];
                system += [[loadSystem objectAtIndex: loadIndex] floatValue];
            }
            system /= processorCount;
            user /= processorCount;
            [combinedUser addObject: [NSNumber numberWithFloat: user]];
            [combinedSystem addObject: [NSNumber numberWithFloat: system]];
            [loadUser removeAllObjects];
            [loadSystem removeAllObjects];
            loadUser = combinedUser;
            loadSystem = combinedSystem;
        }
    }

    // Build the loadInfo dictionaries from the (possibly sorted) user and system load values

	NSMutableArray *loadInfo = [NSMutableArray array];

	for (natural_t i = 0; i < [loadUser count]; i++) {
		[loadInfo addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                                             [loadSystem objectAtIndex:i], @"system",
                                             [loadUser objectAtIndex:i], @"user",
                                          nil]];
    }

	// Dealloc
	vm_deallocate(mach_task_self(), (vm_address_t)processorTickInfo, (vm_size_t)(processorInfoCount * sizeof(natural_t)));

	// Send the gathered data back
	return loadInfo;

} // currentLoad

///////////////////////////////////////////////////////////////
//
//	Utility
//
///////////////////////////////////////////////////////////////

- (NSString *)cpuPrettyName {

#if  __i386__ || __x86_64__
	// Intel Core Duo/Solo and later reported as 80486, just call
	// everything "Intel"
	return @"Intel";
#else
	// Start with nothing
	NSString					*prettyName = @"Unknown CPU";

	// Try older API for the pretty name (Aquamon demonstrated this)
	NXArchInfo const *archInfo = NXGetLocalArchInfo();
	if (archInfo) {
		prettyName = [NSString stringWithCString:archInfo->description];
	}

	// Now try to do better for 7455 Apollo, 7447 AlBooks, and Sahara G3s.
	// Note that this still doesn't work for some 7455s in 10.2.
	// Since those same machines return the correct type in Classic
	// I'm assuming its an Apple bug.
	SInt32 gestaltVal = 0;
	OSStatus err = Gestalt(gestaltNativeCPUtype, &gestaltVal);
	if (err == noErr) {
		if (gestaltVal == gestaltCPUApollo) {
			prettyName = @"PowerPC 7455";
		} else if (gestaltVal == gestaltCPUG47447) {
			// Gestalt says 7447, but CHUD says 7457. Let's believe CHUD.
			// Patch from Alex Eddy
			prettyName = @"PowerPC 7457";
		} else if (gestaltVal == gestaltCPU750FX) {
			prettyName = @"PowerPC 750fx";
		}
	}
	return prettyName;
#endif

} // _cpuPrettyName

@end
