//
//  MenuMeterNetExtra.m
//
//	Menu Extra implementation
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

#import "MenuMeterNetExtra.h"


///////////////////////////////////////////////////////////////
//
//	Private methods and constants
//
///////////////////////////////////////////////////////////////

// Apple network settings we'll try to use
#define kAppleNetworkConnectDefaultsDomain CFSTR("com.apple.networkConnect")

@interface MenuMeterNetExtra (PrivateMethods)

// Image renderers
- (void)renderGraphIntoImage:(NSImage *)image;
- (void)renderActivityIntoImage:(NSImage *)image;
- (void)renderThroughputIntoImage:(NSImage *)image;

// Timer callbacks
- (void)updateNetActivityDisplay:(NSTimer *)timer;
- (void)updateMenuWhenDown;

// Menu actions
- (void)openNetworkUtil:(id)sender;
- (void)openNetworkPrefs:(id)sender;
- (void)openInternetConnect:(id)sender;
- (void)switchDisplay:(id)sender;
- (void)copyAddress:(id)sender;
- (void)pppConnect:(id)sender;
- (void)pppDisconnect:(id)sender;

// Prefs
- (void)configFromPrefs:(NSNotification *)notification;

// Data formatting
- (NSString *)throughputStringForBPS:(double)bps;
- (NSString *)throughputStringForBytes:(double)bytes inInterval:(NSTimeInterval)interval;
- (NSString *)menubarThroughputStringForBytes:(double)bytes inInterval:(NSTimeInterval)interval;
- (NSString *)stringForBytes:(double)bytes;

@end

///////////////////////////////////////////////////////////////
//
//	Localized strings
//
///////////////////////////////////////////////////////////////

#define kTxLabel						@"Tx:"
#define kRxLabel						@"Rx:"
#define kPPPTitle						@"PPP:"
#define kTCPIPTitle						@"TCP/IP:"
#define kIPv4Title						@"IPv4:"
#define kIPv6Title						@"IPv6:"
#define kTCPIPInactiveTitle				@"Inactive"
#define kAppleTalkTitle					@"AppleTalk:"
#define kAppleTalkFormat				@"Net: %@ Node: %@ Zone: %@"
#define kThroughputTitle				@"Throughput:"
#define kPeakThroughputTitle			@"Peak Throughput:"
#define kTrafficTotalTitle				@"Traffic Totals:"
#define kTrafficTotalFormat				@"%@ %@ (%@ bytes)"
#define kOpenNetworkUtilityTitle		@"Open Network Utility"
#define kOpenNetworkPrefsTitle			@"Open Network Preferences"
#define kOpenInternetConnectTitle		@"Open Internet Connect"
#define kSelectPrimaryInterfaceTitle	@"Display primary interface"
#define kSelectInterfaceTitle			@"Display this interface"
#define kCopyIPv4Title					@"Copy IPv4 address"
#define kCopyIPv6Title					@"Copy IPv6 address"
#define kPPPConnectTitle				@"Connect"
#define kPPPDisconnectTitle				@"Disconnect"
#define kNoInterfaceErrorMessage		@"No Active Interfaces"
#define kGbpsLabel						@"Gbps"
#define kMbpsLabel						@"Mbps"
#define kKbpsLabel						@"Kbps"
#define kByteLabel						@"B"
#define kKBLabel						@"KB"
#define kMBLabel						@"MB"
#define kGBLabel						@"GB"
#define kBytePerSecondLabel				@"B/s"
#define kKBPerSecondLabel				@"KB/s"
#define kMBPerSecondLabel				@"MB/s"
#define kGBPerSecondLabel				@"GB/s"
#define kPPPNoConnectTitle				@"Not Connected"
#define kPPPConnectingTitle				@"Connecting..."
#define kPPPConnectedTitle				@"Connected"
#define kPPPConnectedWithTimeTitle		@"Connected %02d:%02d:%02d"
#define kPPPDisconnectingTitle			@"Disconnecting..."

///////////////////////////////////////////////////////////////
//
//	init/unload/dealloc
//
///////////////////////////////////////////////////////////////

@implementation MenuMeterNetExtra

- initWithBundle:(NSBundle *)bundle {

	self = [super initWithBundle:bundle];
	if (!self) {
		return nil;
	}

	// Panther check
	SInt32 systemVersion = 0;
	OSStatus err = Gestalt(gestaltSystemVersion, &systemVersion);
	if (err != noErr) {
		[self release];
		return nil;
	}
	isPantherOrLater = NO;
	if (systemVersion >= 0x1030) {
		isPantherOrLater = YES;
	}
	if (systemVersion >= 0x1050) {
		isLeopardOrLater = YES;
	}

	// Load our pref bundle, we do this as a bundle because we are a plugin
	// to SystemUIServer and as a result cannot have the same class loaded
	// from every meter. Using a shared bundle each loads fixes this.
	NSString *prefBundlePath = [[[bundle bundlePath] stringByDeletingLastPathComponent]
								stringByAppendingPathComponent:kPrefBundleName];
	ourPrefs = [[[[NSBundle bundleWithPath:prefBundlePath] principalClass] alloc] init];
	if (!ourPrefs) {
		NSLog(@"MenuMeterCPU unable to connect to preferences. Abort.");
		[self release];
		return nil;
	}

	// Build our data gatherers
	netConfig = [[MenuMeterNetConfig alloc] init];
	netStats = [[MenuMeterNetStats alloc] init];
	pppControl = [[MenuMeterNetPPP sharedPPP] retain];
	netHistoryData = [[NSMutableArray array] retain];
	netHistoryIntervals = [[NSMutableArray array] retain];
	if (!(netConfig && netStats && pppControl && netHistoryData)) {
		NSLog(@"MenuMeterNet unable to load data gatherers/controllers. Abort.");
		[self release];
		return nil;
	}

	// Setup our menu
	extraMenu = [[NSMenu alloc] initWithTitle:@""];
	if (!extraMenu) {
		[self release];
		return nil;
	}
	// Disable menu autoenabling
	[extraMenu setAutoenablesItems:NO];

	// Menu is regenerated in the menu method always so no futher setup

	// Set the menu extra view up
	// Get our view
    extraView = [[MenuMeterNetView alloc] initWithFrame:[[self view] frame] menuExtra:self];
	if (!extraView) {
		[self release];
		return nil;
	}
    [self setView:extraView];

	// Localizable strings
	localizedStrings = [[NSDictionary dictionaryWithObjectsAndKeys:
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kTxLabel value:nil table:nil],
							kTxLabel,
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kRxLabel value:nil table:nil],
							kRxLabel,
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kPPPTitle value:nil table:nil],
							kPPPTitle,
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kTCPIPTitle value:nil table:nil],
							kTCPIPTitle,
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kIPv4Title value:nil table:nil],
							kIPv4Title,
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kIPv6Title value:nil table:nil],
							kIPv6Title,
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kTCPIPInactiveTitle value:nil table:nil],
							kTCPIPInactiveTitle,
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kAppleTalkTitle value:nil table:nil],
							kAppleTalkTitle,
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kAppleTalkFormat value:nil table:nil],
							kAppleTalkFormat,
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kThroughputTitle value:nil table:nil],
							kThroughputTitle,
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kPeakThroughputTitle value:nil table:nil],
							kPeakThroughputTitle,
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kTrafficTotalTitle value:nil table:nil],
							kTrafficTotalTitle,
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kTrafficTotalFormat value:nil table:nil],
							kTrafficTotalFormat,
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kOpenNetworkUtilityTitle value:nil table:nil],
							kOpenNetworkUtilityTitle,
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kOpenNetworkPrefsTitle value:nil table:nil],
							kOpenNetworkPrefsTitle,
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kOpenInternetConnectTitle value:nil table:nil],
							kOpenInternetConnectTitle,
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kNoInterfaceErrorMessage value:nil table:nil],
							kNoInterfaceErrorMessage,
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kSelectPrimaryInterfaceTitle value:nil table:nil],
							kSelectPrimaryInterfaceTitle,
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kSelectInterfaceTitle value:nil table:nil],
							kSelectInterfaceTitle,
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kCopyIPv4Title value:nil table:nil],
							kCopyIPv4Title,
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kCopyIPv6Title value:nil table:nil],
							kCopyIPv6Title,
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kPPPConnectTitle value:nil table:nil],
							kPPPConnectTitle,
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kPPPDisconnectTitle value:nil table:nil],
							kPPPDisconnectTitle,
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kGbpsLabel value:nil table:nil],
							kGbpsLabel,
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kMbpsLabel value:nil table:nil],
							kMbpsLabel,
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kKbpsLabel value:nil table:nil],
							kKbpsLabel,
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kByteLabel value:nil table:nil],
							kByteLabel,
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kKBLabel value:nil table:nil],
							kKBLabel,
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kMBLabel value:nil table:nil],
							kMBLabel,
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kGBLabel value:nil table:nil],
							kGBLabel,
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kBytePerSecondLabel value:nil table:nil],
							kBytePerSecondLabel,
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kKBPerSecondLabel value:nil table:nil],
							kKBPerSecondLabel,
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kMBPerSecondLabel value:nil table:nil],
							kMBPerSecondLabel,
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kGBPerSecondLabel value:nil table:nil],
							kGBPerSecondLabel,
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kPPPNoConnectTitle value:nil table:nil],
							kPPPNoConnectTitle,
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kPPPConnectingTitle value:nil table:nil],
							kPPPConnectingTitle,
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kPPPConnectedTitle value:nil table:nil],
							kPPPConnectedTitle,
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kPPPConnectedWithTimeTitle value:nil table:nil],
							kPPPConnectedWithTimeTitle,
							[[NSBundle bundleForClass:[self class]] localizedStringForKey:kPPPDisconnectingTitle value:nil table:nil],
							kPPPDisconnectingTitle,
							nil] retain];

	// Set up a NumberFormatter for localization. This is based on code contributed by Mike Fischer
	// (mike.fischer at fi-works.de) for use in MenuMeters.
	NSNumberFormatter *tempFormat = [[[NSNumberFormatter alloc] init] autorelease];
	[tempFormat setLocalizesFormat:YES];
	[tempFormat setFormat:@"###0.0"];
	// Go through an archive/unarchive cycle to work around a bug on pre-10.2.2 systems
	// see http://cocoa.mamasam.com/COCOADEV/2001/12/2/21029.php
	bytesFormatter = [[NSUnarchiver unarchiveObjectWithData:[NSArchiver archivedDataWithRootObject:tempFormat]] retain];
	tempFormat = [[[NSNumberFormatter alloc] init] autorelease];
	[tempFormat setLocalizesFormat:YES];
	[tempFormat setFormat:@"#,##0"];
	prettyIntFormatter = [[NSUnarchiver unarchiveObjectWithData:[NSArchiver archivedDataWithRootObject:tempFormat]] retain];

	// Register for pref changes
	[[NSDistributedNotificationCenter defaultCenter] addObserver:self
														selector:@selector(configFromPrefs:)
															name:kNetMenuBundleID
														  object:kPrefChangeNotification];
	// And configure directly from prefs on first load
	[self configFromPrefs:nil];

	// Fake a timer call to config initial values
	[self updateNetActivityDisplay:nil];

    // And hand ourself back to SystemUIServer
	NSLog(@"MenuMeterNet loaded.");
    return self;

} // initWithBundle

- (void)willUnload {

	// Stop the timer
	[updateTimer invalidate];  // Released by the runloop
	updateTimer = nil;

	// Unregister pref change notifications
	[[NSDistributedNotificationCenter defaultCenter] removeObserver:self
															   name:nil
															 object:nil];

	// Let the pref panel know we have been removed
	[[NSDistributedNotificationCenter defaultCenter] postNotificationName:kNetMenuBundleID
																   object:kNetMenuUnloadNotification];

	// Let super do the rest
    [super willUnload];

} // willUnload

- (void)dealloc {

	[extraView release];
    [extraMenu release];
	[updateTimer invalidate];  // Released by the runloop
	[ourPrefs release];
	[netConfig release];
	[netStats release];
	[pppControl release];
	[localizedStrings release];
	[bytesFormatter release];
	[prettyIntFormatter release];
	[txColor release];
	[rxColor release];
	[inactiveColor release];
	[lastSampleDate release];
	[netHistoryData release];
	[netHistoryIntervals release];
	[upArrow release];
	[downArrow release];
	[throughputLabel release];
	[inactiveThroughputLabel release];
	[preferredInterfaceConfig release];
	[updateMenuItems release];
    [super dealloc];

} // dealloc

///////////////////////////////////////////////////////////////
//
//	NSMenuExtra view callbacks
//
///////////////////////////////////////////////////////////////

- (NSImage *)image {

	// Image to render into (and return to view)
	NSImage *currentImage = [[[NSImage alloc] initWithSize:NSMakeSize((float)menuWidth,
																	  [extraView frame].size.height - 1)] autorelease];
	if (!currentImage) return nil;

	// Don't render without data
	if (![netHistoryData count]) return nil;

	// Draw displays
	if ([ourPrefs netDisplayMode] & kNetDisplayGraph) {
		[self renderGraphIntoImage:currentImage];
	}
	if ([ourPrefs netDisplayMode] & kNetDisplayArrows) {
		[self renderActivityIntoImage:currentImage];
	}
	if ([ourPrefs netDisplayMode] & kNetDisplayThroughput) {
		[self renderThroughputIntoImage:currentImage];
	}

	// Send it back for the view to render
	return currentImage;

} // image

// Boy does this need refactoring... *sigh*
- (NSMenu *)menu {

	// New cache
	[updateMenuItems release];
	updateMenuItems = [[NSMutableDictionary dictionary] retain];//

	// Empty the menu
	while ([extraMenu numberOfItems]) {
		[extraMenu removeItemAtIndex:0];
	}

	// Hostname
	NSString *hostname = [[netConfig computerName] retain];
	if (hostname) {
		[[extraMenu addItemWithTitle:hostname action:nil keyEquivalent:@""] setEnabled:NO];
		[extraMenu addItem:[NSMenuItem separatorItem]];
	}

	// Interface detail array
	BOOL pppPresent = NO;
	NSArray *interfaceDetails = [netConfig interfaceDetails];
	if ([interfaceDetails count]) {
		NSEnumerator *detailEnum = [interfaceDetails objectEnumerator];
		NSDictionary *details = nil;
		while ((details = [detailEnum nextObject])) {
			// Array entry is a service/interface
			NSMutableDictionary *interfaceUpdateMenuItems = [NSMutableDictionary dictionary];
			NSString *interfaceDescription = [details objectForKey:@"name"];
			NSString *speed = nil;
			BOOL foundSelectedInterface = NO;
			// Best guess if this is an active interface, default to assume it is active
			BOOL isActiveInterface = YES;
			if ([details objectForKey:@"linkactive"]) {
				isActiveInterface = [[details objectForKey:@"linkactive"] boolValue];
			}
			if ([details objectForKey:@"pppstatus"]) {
				if ([(NSNumber *)[[details objectForKey:@"pppstatus"] objectForKey:@"status"] unsignedIntValue] == PPP_IDLE) {
					isActiveInterface = NO;
				}
			}
			// Calc speed
			if ([details objectForKey:@"linkspeed"] && isActiveInterface) {
				if ([[details objectForKey:@"linkspeed"] doubleValue] > 1000000000) {
					speed = [NSString stringWithFormat:@" %.0f%@",
								([[details objectForKey:@"linkspeed"] doubleValue] / 1000000000),
								[localizedStrings objectForKey:kGbpsLabel]];
				} else if ([[details objectForKey:@"linkspeed"] doubleValue] > 1000000) {
					speed = [NSString stringWithFormat:@" %.0f%@",
								([[details objectForKey:@"linkspeed"] doubleValue] / 1000000),
								[localizedStrings objectForKey:kMbpsLabel]];
				} else {
					speed = [NSString stringWithFormat:@" %@%@",
								[bytesFormatter stringForObjectValue:
									[NSNumber numberWithDouble:([[details objectForKey:@"linkspeed"] doubleValue] / 1000)]],
								[localizedStrings objectForKey:kKbpsLabel]];
				}
			}
			// Weird string cat because some of these values may not be present
			// Also skip device name bit if the driver name (UserDefined name) already includes it (SourceForge wireless driver)
			if ([details objectForKey:@"devicename"] &&
				![interfaceDescription hasSuffix:[NSString stringWithFormat:@"(%@)", [details objectForKey:@"devicename"]]]) {
				// If there is a PPP name use it too
				if ([details objectForKey:@"devicepppname"]) {
					interfaceDescription = [NSString stringWithFormat:@"%@ (%@, %@)",
												interfaceDescription,
												[details objectForKey:@"devicename"],
												[details objectForKey:@"devicepppname"]];
				} else {
					interfaceDescription = [NSString stringWithFormat:@"%@ (%@)",
												interfaceDescription,
												[details objectForKey:@"devicename"]];
				}
			}
			if (speed || [details objectForKey:@"connectiontype"]) {
				interfaceDescription = [NSString stringWithFormat:@"%@ -%@%@",
											interfaceDescription,
											([details objectForKey:@"connectiontype"] ?
												[NSString stringWithFormat:@" %@", [details objectForKey:@"connectiontype"]] : @""),
											(speed ? speed : @"")];
			}
			NSMenuItem *titleItem = (NSMenuItem *)[extraMenu addItemWithTitle:interfaceDescription action:nil keyEquivalent:@""];
			// PPP Status
			if ([details objectForKey:@"pppstatus"]) {
				// PPP is present
				pppPresent = YES;
				NSMenuItem *pppStatusItem = nil;
				// Use the connection type title for PPP when we can
				if ([details objectForKey:@"connectiontype"]) {
					[[extraMenu addItemWithTitle:[NSString stringWithFormat:kMenuIndentFormat,
												  [NSString stringWithFormat:@"%@:", [details objectForKey:@"connectiontype"]]]
										  action:nil
								   keyEquivalent:@""] setEnabled:NO];
				} else {
					[[extraMenu addItemWithTitle:[NSString stringWithFormat:kMenuIndentFormat, [localizedStrings objectForKey:kPPPTitle]]
										  action:nil
								   keyEquivalent:@""] setEnabled:NO];
				}
				switch ([(NSNumber *)[[details objectForKey:@"pppstatus"] objectForKey:@"status"] unsignedIntValue]) {
					case PPP_IDLE:
						pppStatusItem = (NSMenuItem *)[extraMenu addItemWithTitle:[NSString stringWithFormat:kMenuDoubleIndentFormat,
																					[localizedStrings objectForKey:kPPPNoConnectTitle]]
																		   action:nil
																	keyEquivalent:@""];
						break;
					case PPP_INITIALIZE:
					case PPP_CONNECTLINK:
					case PPP_STATERESERVED:
					case PPP_ESTABLISH:
					case PPP_AUTHENTICATE:
					case PPP_CALLBACK:
					case PPP_NETWORK:
					case PPP_HOLDOFF:
					case PPP_ONHOLD:
					case PPP_WAITONBUSY:
						pppStatusItem = (NSMenuItem *)[extraMenu addItemWithTitle:[NSString stringWithFormat:kMenuDoubleIndentFormat,
																					[localizedStrings objectForKey:kPPPConnectingTitle]]
																		   action:nil
																	keyEquivalent:@""];
						break;
					case PPP_RUNNING:
						if ([[details objectForKey:@"pppstatus"] objectForKey:@"timeElapsed"]) {
							uint32_t secs = [[[details objectForKey:@"pppstatus"] objectForKey:@"timeElapsed"] unsignedIntValue];
							uint32_t hours = secs / (60 * 60);
							secs %= (60 * 60);
							uint32_t mins = secs / 60;
							secs %= 60;
							pppStatusItem = (NSMenuItem *)[extraMenu addItemWithTitle:[NSString stringWithFormat:kMenuDoubleIndentFormat,
																							[NSString stringWithFormat:
																								[localizedStrings objectForKey:kPPPConnectedWithTimeTitle],
																								hours, mins, secs]]
																			   action:nil
																		keyEquivalent:@""];
						} else {
							pppStatusItem = (NSMenuItem *)[extraMenu addItemWithTitle:[NSString stringWithFormat:kMenuDoubleIndentFormat, kPPPConnectedTitle]
																			   action:nil
																		keyEquivalent:@""];
						}
						break;
					case PPP_TERMINATE:
					case PPP_DISCONNECTLINK:
						pppStatusItem = (NSMenuItem *)[extraMenu addItemWithTitle:[NSString stringWithFormat:kMenuIndentFormat,
																					[localizedStrings objectForKey:kPPPDisconnectingTitle]]
																		   action:nil
																	keyEquivalent:@""];
						break;
				};
				if (pppStatusItem) {
					[pppStatusItem setEnabled:NO];
					[interfaceUpdateMenuItems setObject:pppStatusItem forKey:@"pppstatusitem"];
				}
			}
			// TCP/IP
			[[extraMenu addItemWithTitle:[NSString stringWithFormat:kMenuIndentFormat, [localizedStrings objectForKey:kTCPIPTitle]]
								  action:nil
						   keyEquivalent:@""] setEnabled:NO];
			if ([[details objectForKey:@"ipv4addresses"] count] && [[details objectForKey:@"ipv6addresses"] count]) {
				[[extraMenu addItemWithTitle:[NSString stringWithFormat:kMenuDoubleIndentFormat, [localizedStrings objectForKey:kIPv4Title]]
									  action:nil
							   keyEquivalent:@""] setEnabled:NO];
				NSEnumerator *addressEnum = [[details objectForKey:@"ipv4addresses"] objectEnumerator];
				NSString *address = nil;
				while ((address = [addressEnum nextObject])) {
					[[extraMenu addItemWithTitle:[NSString stringWithFormat:kMenuTripleIndentFormat, address]
										  action:nil
								   keyEquivalent:@""] setEnabled:NO];
				}
				[[extraMenu addItemWithTitle:[NSString stringWithFormat:kMenuDoubleIndentFormat, [localizedStrings objectForKey:kIPv6Title]]
									  action:nil
							   keyEquivalent:@""] setEnabled:NO];
				addressEnum = [[details objectForKey:@"ipv6addresses"] objectEnumerator];
				while ((address = [addressEnum nextObject])) {
					[[extraMenu addItemWithTitle:[NSString stringWithFormat:kMenuTripleIndentFormat, address]
										  action:nil
								   keyEquivalent:@""] setEnabled:NO];
				}
			} else if ([[details objectForKey:@"ipv4addresses"] count]) {
				NSEnumerator *addressEnum = [[details objectForKey:@"ipv4addresses"] objectEnumerator];
				NSString *address = nil;
				while ((address = [addressEnum nextObject])) {
					[[extraMenu addItemWithTitle:[NSString stringWithFormat:kMenuDoubleIndentFormat, address]
										  action:nil
								   keyEquivalent:@""] setEnabled:NO];
				}
			} else {
				[[extraMenu addItemWithTitle:[NSString stringWithFormat:kMenuDoubleIndentFormat,
													[localizedStrings objectForKey:kTCPIPInactiveTitle]]
									  action:nil
							   keyEquivalent:@""] setEnabled:NO];
			}
			// AppleTalk
			if ([details objectForKey:@"appletalknetid"]) {
				[[extraMenu addItemWithTitle:[NSString stringWithFormat:kMenuIndentFormat,
												[localizedStrings objectForKey:kAppleTalkTitle]]
									  action:nil
							   keyEquivalent:@""] setEnabled:NO];
				[[extraMenu addItemWithTitle:[NSString stringWithFormat:kMenuDoubleIndentFormat,
													[NSString stringWithFormat:[localizedStrings objectForKey:kAppleTalkFormat],
														[details objectForKey:@"appletalknetid"],
														[details objectForKey:@"appletalknodeid"],
														[details objectForKey:@"appletalkzone"]]]
									  action:nil
							   keyEquivalent:@""] setEnabled:NO];
			}
			// Throughput
			NSNumber *sampleIntervalNum = [netHistoryIntervals lastObject];
			NSDictionary *throughputDetails = nil;
			NSString *throughputInterface = nil;
			// Do some dancing to make sure to get serial and VPN PPP interfaces, but not PPPoE
			if ([netHistoryData lastObject] && ([details objectForKey:@"devicename"] || [details objectForKey:@"devicepppname"])) {
				if ([details objectForKey:@"devicepppname"] && ![[details objectForKey:@"devicename"] hasPrefix:@"en"]) {
					throughputInterface = [details objectForKey:@"devicepppname"];
					throughputDetails = [[netHistoryData lastObject] objectForKey:[details objectForKey:@"devicepppname"]];
				} else {
					throughputInterface = [details objectForKey:@"devicename"];
					throughputDetails = [[netHistoryData lastObject] objectForKey:[details objectForKey:@"devicename"]];
				}
			}
			// Do we have throughput info on an active interface?
			if (isActiveInterface && sampleIntervalNum && throughputInterface && throughputDetails) {
				NSNumber *throughputOutNumber = [throughputDetails objectForKey:@"deltaout"];
				NSNumber *throughputInNumber = [throughputDetails objectForKey:@"deltain"];
				if (throughputOutNumber && throughputInNumber) {
					[[extraMenu addItemWithTitle:[NSString stringWithFormat:kMenuIndentFormat, [localizedStrings objectForKey:kThroughputTitle]]
										  action:nil
								   keyEquivalent:@""] setEnabled:NO];
					NSMenuItem *throughputItem = (NSMenuItem *)[extraMenu addItemWithTitle:[NSString stringWithFormat:kMenuDoubleIndentFormat,
																								[NSString stringWithFormat:@"%@ %@",
																									[localizedStrings objectForKey:kTxLabel],
																									[self throughputStringForBytes:[throughputOutNumber doubleValue]
																														inInterval:[sampleIntervalNum doubleValue]]]]
																				   action:nil
																			keyEquivalent:@""];
					[throughputItem setEnabled:NO];
					[interfaceUpdateMenuItems setObject:throughputItem forKey:@"deltaoutitem"];
					throughputItem = (NSMenuItem *)[extraMenu addItemWithTitle:[NSString stringWithFormat:kMenuDoubleIndentFormat,
																					[NSString stringWithFormat:@"%@ %@",
																						 [localizedStrings objectForKey:kRxLabel],
																						 [self throughputStringForBytes:[throughputInNumber doubleValue]
																											 inInterval:[sampleIntervalNum doubleValue]]]]
																		action:nil
																 keyEquivalent:@""];
					[throughputItem setEnabled:NO];
					[interfaceUpdateMenuItems setObject:throughputItem forKey:@"deltainitem"];
				}
				// Add peak throughput
				NSNumber *peakNumber = [throughputDetails objectForKey:@"peak"];
				if (peakNumber) {
					[[extraMenu addItemWithTitle:[NSString stringWithFormat:kMenuIndentFormat, [localizedStrings objectForKey:kPeakThroughputTitle]]
										  action:nil
								   keyEquivalent:@""] setEnabled:NO];
					NSMenuItem *peakItem = (NSMenuItem *)[extraMenu addItemWithTitle:[NSString stringWithFormat:kMenuDoubleIndentFormat,
																						[self throughputStringForBPS:[peakNumber doubleValue]]]
																			  action:nil
																	   keyEquivalent:@""];
					[peakItem setEnabled:NO];
					[interfaceUpdateMenuItems setObject:peakItem forKey:@"peakitem"];
				}
				// Add traffic totals
				throughputOutNumber = [throughputDetails objectForKey:@"totalout"];
				throughputInNumber = [throughputDetails objectForKey:@"totalin"];
				if (throughputOutNumber && throughputInNumber) {
					[[extraMenu addItemWithTitle:[NSString stringWithFormat:kMenuIndentFormat, [localizedStrings objectForKey:kTrafficTotalTitle]]
										  action:nil
								   keyEquivalent:@""] setEnabled:NO];
					NSMenuItem *totalItem = (NSMenuItem *)[extraMenu addItemWithTitle:[NSString stringWithFormat:kMenuDoubleIndentFormat,
																							[NSString stringWithFormat:[localizedStrings objectForKey:kTrafficTotalFormat],
																								[localizedStrings objectForKey:kTxLabel],
																								[self stringForBytes:[throughputOutNumber doubleValue]],
																								[prettyIntFormatter stringForObjectValue:throughputOutNumber]]]
																			   action:nil
																		keyEquivalent:@""];
					[totalItem setEnabled:NO];
					[interfaceUpdateMenuItems setObject:totalItem forKey:@"totaloutitem"];
					totalItem = (NSMenuItem *)[extraMenu addItemWithTitle:[NSString stringWithFormat:kMenuDoubleIndentFormat,
																				[NSString stringWithFormat:[localizedStrings objectForKey:kTrafficTotalFormat],
																					[localizedStrings objectForKey:kRxLabel],
																					[self stringForBytes:[throughputInNumber doubleValue]],
																					[prettyIntFormatter stringForObjectValue:throughputInNumber]]]
																   action:nil
															keyEquivalent:@""];
					[totalItem setEnabled:NO];
					[interfaceUpdateMenuItems setObject:totalItem forKey:@"totalinitem"];
				}
				// Store the name to use in throughput reads for items we will update later
				[interfaceUpdateMenuItems setObject:throughputInterface forKey:@"throughinterface"];
			}

			// Store the update items we built for this interface if needed
			if ([interfaceUpdateMenuItems count]) {
				[updateMenuItems setObject:interfaceUpdateMenuItems forKey:[details objectForKey:@"service"]];
			}

			// Now set up the submenu for this interface
			NSMenu *interfaceSubmenu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
			// Disable menu autoenabling
			[interfaceSubmenu setAutoenablesItems:NO];
			// Add the submenu
			[titleItem setSubmenu:interfaceSubmenu];
			// PPP controller if needed and we can control the connection type on this OS version
			if ([details objectForKey:@"pppstatus"] &&
				([[details objectForKey:@"connectiontype"] isEqualToString:@"PPP"] || isPantherOrLater)) {
				NSMenuItem *pppControlItem = nil;
				switch ([(NSNumber *)[[details objectForKey:@"pppstatus"] objectForKey:@"status"] unsignedIntValue]) {
					case PPP_IDLE:
						pppControlItem = (NSMenuItem *)[interfaceSubmenu addItemWithTitle:[localizedStrings objectForKey:kPPPConnectTitle]
																				   action:@selector(pppConnect:)
																			keyEquivalent:@""];
						break;
					case PPP_INITIALIZE:
					case PPP_CONNECTLINK:
					case PPP_STATERESERVED:
					case PPP_ESTABLISH:
					case PPP_AUTHENTICATE:
					case PPP_CALLBACK:
					case PPP_NETWORK:
					case PPP_HOLDOFF:
					case PPP_ONHOLD:
					case PPP_WAITONBUSY:
					case PPP_RUNNING:
						pppControlItem = (NSMenuItem *)[interfaceSubmenu addItemWithTitle:[localizedStrings objectForKey:kPPPDisconnectTitle]
																				   action:@selector(pppDisconnect:)
																			keyEquivalent:@""];
						break;
					case PPP_TERMINATE:
					case PPP_DISCONNECTLINK:
						pppControlItem = (NSMenuItem *)[interfaceSubmenu addItemWithTitle:[localizedStrings objectForKey:kPPPConnectTitle]
																				   action:@selector(pppConnect:)
																			keyEquivalent:@""];
						break;
				};
				[pppControlItem setTarget:self];
				[pppControlItem setRepresentedObject:[details objectForKey:@"service"]];
				[interfaceSubmenu addItem:[NSMenuItem separatorItem]];
			}
			// Add interface selection submenus
			BOOL hadInterfaceSelector = NO;
			if ([[details objectForKey:@"primary"] boolValue]) {
				NSMenuItem *primarySwitchItem = (NSMenuItem *)[interfaceSubmenu addItemWithTitle:[localizedStrings objectForKey:kSelectPrimaryInterfaceTitle]
																						  action:@selector(switchDisplay:)
																				   keyEquivalent:@""];
				[primarySwitchItem setRepresentedObject:kNetPrimaryInterface];
				[primarySwitchItem setTarget:self];
				if ([[ourPrefs netPreferInterface] isEqualToString:kNetPrimaryInterface]) {
					[primarySwitchItem setEnabled:NO];
				} else {
					[primarySwitchItem setEnabled:YES];
				}
				hadInterfaceSelector = YES;
			}
			// Other choose interface
			if ([details objectForKey:@"devicename"]) {
				NSMenuItem *interfaceSwitchItem = (NSMenuItem *)[interfaceSubmenu addItemWithTitle:[localizedStrings objectForKey:kSelectInterfaceTitle]
																							action:@selector(switchDisplay:)
																					 keyEquivalent:@""];
				[interfaceSwitchItem setRepresentedObject:[details objectForKey:@"devicename"]];
				[interfaceSwitchItem setTarget:self];
				// Disable if this is preferred
				if ([[details objectForKey:@"devicename"] isEqualToString:[ourPrefs netPreferInterface]]) {
					[interfaceSwitchItem setEnabled:NO];
				}
				hadInterfaceSelector = YES;
			}
			if (hadInterfaceSelector) {
				[interfaceSubmenu addItem:[NSMenuItem separatorItem]];
			}
			// Checkmark the interface menu if we haven't found one already
			if (!foundSelectedInterface) {
				if ([[ourPrefs netPreferInterface] isEqualToString:kNetPrimaryInterface] && [[details objectForKey:@"primary"] boolValue]) {
					// This is the primary and the primary is preferred
					[titleItem setState:NSOnState];
					foundSelectedInterface = YES;
				} else if (preferredInterfaceConfig && [details objectForKey:@"devicename"]) {
					// Is this device the one being graphed?
					if ([[details objectForKey:@"devicename"] isEqualToString:[preferredInterfaceConfig objectForKey:@"name"]] ||
						[[details objectForKey:@"devicename"] isEqualToString:[preferredInterfaceConfig objectForKey:@"statname"]]) {
						[titleItem setState:NSOnState];
						foundSelectedInterface = YES;
					}
				} else if (preferredInterfaceConfig && [details objectForKey:@"devicepppname"]) {
					if ([[details objectForKey:@"devicepppname"] isEqualToString:[preferredInterfaceConfig objectForKey:@"name"]] ||
						[[details objectForKey:@"devicepppname"] isEqualToString:[preferredInterfaceConfig objectForKey:@"statname"]]) {
						[titleItem setState:NSOnState];
						foundSelectedInterface = YES;
					}
				}
			}
			// Copy IP
			NSMenuItem *copyIPItem = (NSMenuItem *)[interfaceSubmenu addItemWithTitle:[localizedStrings objectForKey:kCopyIPv4Title]
																			   action:@selector(copyAddress:)
																		keyEquivalent:@""];
			[copyIPItem setTarget:self];
			if ([[details objectForKey:@"ipv4addresses"] count]) {
				[copyIPItem setRepresentedObject:[details objectForKey:@"ipv4addresses"]];
			} else {
				[copyIPItem setEnabled:NO];
			}
			if ([[details objectForKey:@"ipv6addresses"] count]) {
				copyIPItem = (NSMenuItem *)[interfaceSubmenu addItemWithTitle:[localizedStrings objectForKey:kCopyIPv6Title]
																	   action:@selector(copyAddress:)
																keyEquivalent:@""];
				[copyIPItem setTarget:self];
				if ([[details objectForKey:@"ipv6addresses"] count]) {
					[copyIPItem setRepresentedObject:[details objectForKey:@"ipv6addresses"]];
				} else {
					[copyIPItem setEnabled:NO];
				}
			}
		}
	} else {
		[[extraMenu addItemWithTitle:[localizedStrings objectForKey:kNoInterfaceErrorMessage]
							  action:nil
					   keyEquivalent:@""] setEnabled:NO];
	}

	// Add utility items
	[extraMenu addItem:[NSMenuItem separatorItem]];
	[[extraMenu addItemWithTitle:[localizedStrings objectForKey:kOpenNetworkUtilityTitle]
						  action:@selector(openNetworkUtil:)
				   keyEquivalent:@""] setTarget:self];
	[[extraMenu addItemWithTitle:[localizedStrings objectForKey:kOpenNetworkPrefsTitle]
						  action:@selector(openNetworkPrefs:)
				   keyEquivalent:@""] setTarget:self];
	// Open Internet Connect if PPP
	if (pppPresent && !isLeopardOrLater) {
		[[extraMenu addItemWithTitle:[localizedStrings objectForKey:kOpenInternetConnectTitle]
							  action:@selector(openInternetConnect:)
					   keyEquivalent:@""] setTarget:self];
	}

	// Send the menu back to SystemUIServer
	return extraMenu;

} // menu

///////////////////////////////////////////////////////////////
//
//	Image renderers
//
///////////////////////////////////////////////////////////////

- (void)renderGraphIntoImage:(NSImage *)image {

	// Cache style and other values for duration of this method
	int graphStyle = [ourPrefs netGraphStyle];
	BOOL rxOnTop = ([ourPrefs netDisplayOrientation] == kNetDisplayOrientRxTx) ? YES : NO;
	NSSize imageSize = [image size];
	float graphHeight = (float)floor((imageSize.height - 1) / 2);

	// Graph paths
	NSBezierPath *topPath = [NSBezierPath bezierPath];
	NSBezierPath *bottomPath = [NSBezierPath bezierPath];
	if ((graphStyle == kNetGraphStyleOpposed) || (graphStyle == kNetGraphStyleInverseOpposed)) {
		[bottomPath moveToPoint:NSMakePoint(0, 0)];
		[bottomPath lineToPoint:NSMakePoint(0, 0.5f)];
		[topPath moveToPoint:NSMakePoint(0, imageSize.height)];
		[topPath lineToPoint:NSMakePoint(0, imageSize.height - 0.5f)];
	} else if (graphStyle == kNetGraphStyleCentered) {
		[topPath moveToPoint:NSMakePoint(0, graphHeight + 1)];
		[topPath lineToPoint:NSMakePoint(0, graphHeight + 1.5f)];
		[bottomPath moveToPoint:NSMakePoint(0, graphHeight)];
		[bottomPath lineToPoint:NSMakePoint(0, graphHeight - 0.5f)];
	} else {
		[topPath moveToPoint:NSMakePoint(0, graphHeight + 1)];
		[topPath lineToPoint:NSMakePoint(0, graphHeight + 1.5f)];
		[bottomPath moveToPoint:NSMakePoint(0, 0)];
		[bottomPath lineToPoint:NSMakePoint(0, 0.5f)];
	}

	// Get scale (scale is based on latest primary data, not historical)
	float scaleFactor = 0;
	switch ([ourPrefs netScaleMode]) {
		case kNetScaleInterfaceSpeed:
			if ([preferredInterfaceConfig objectForKey:@"speed"]) {
				scaleFactor = [[preferredInterfaceConfig objectForKey:@"speed"] floatValue] / 8;  // Convert to bytes
			}
			break;
		case kNetScalePeakTraffic:
			if (![preferredInterfaceConfig objectForKey:@"statname"]) break;
			if (![netHistoryData count]) break;
			NSDictionary *primaryStats = [[netHistoryData objectAtIndex:0]
										  objectForKey:[preferredInterfaceConfig objectForKey:@"statname"]];
			if (![primaryStats objectForKey:@"peak"]) break;
			scaleFactor = [[primaryStats objectForKey:@"peak"] floatValue];
			break;
	}
	if (scaleFactor > 0) {
		switch ([ourPrefs netScaleCalc]) {
			case kNetScaleCalcLinear:
				// Nothing
				break;
			case kNetScaleCalcSquareRoot:
				scaleFactor = sqrtf(scaleFactor);
				break;
			case kNetScaleCalcCubeRoot:
				scaleFactor = cbrtf(scaleFactor);
				break;
			case kNetScaleCalcLog:
				scaleFactor = logf(scaleFactor);
				break;
		}
	}

	// Loop over pixels in desired width until we're out of data
	int renderPosition = 0;
	float renderHeight = graphHeight - 0.5f;  // Save room for baseline
 	for (renderPosition = 0; renderPosition < [ourPrefs netGraphLength]; renderPosition++) {
		// No data at this position?
		if ((renderPosition >= [netHistoryData count]) ||
			(renderPosition >= [netHistoryIntervals count])) break;

		// Can't scale by zero
		if (scaleFactor <= 0) continue;

		// Grab history data
		NSDictionary *netHistoryEntry = [netHistoryData objectAtIndex:renderPosition];
		if (!netHistoryData) continue;
		float sampleInterval = [[netHistoryIntervals objectAtIndex:renderPosition] floatValue];
		if (sampleInterval <= 0) continue;

		// Grab stats for the primary
		if (![preferredInterfaceConfig objectForKey:@"statname"]) continue;
		NSDictionary *primaryStats = [netHistoryEntry objectForKey:[preferredInterfaceConfig objectForKey:@"statname"]];
		if (!primaryStats) continue;

		// Calc scaled values
		float txValue = [[primaryStats objectForKey:@"deltaout"] floatValue] / sampleInterval;
		float rxValue = [[primaryStats objectForKey:@"deltain"] floatValue] / sampleInterval;
		switch ([ourPrefs netScaleCalc]) {
			case kNetScaleCalcLinear:
				txValue = txValue / scaleFactor;
				rxValue = rxValue / scaleFactor;
				break;
			case kNetScaleCalcSquareRoot:
				txValue = sqrtf(txValue) / scaleFactor;
				rxValue = sqrtf(rxValue) / scaleFactor;
				break;
			case kNetScaleCalcCubeRoot:
				txValue = cbrtf(txValue) / scaleFactor;
				rxValue = cbrtf(rxValue) / scaleFactor;
				break;
			case kNetScaleCalcLog:
				txValue = logf(txValue) / scaleFactor;
				rxValue = logf(rxValue) / scaleFactor;
				break;
		}
		// Bound
		if (txValue > 1) { txValue = 1; }
		if (rxValue > 1) { rxValue = 1; }
		if (txValue < 0) { txValue = 0;	}
		if (rxValue < 0) { rxValue = 0;	}

		// Update paths
		if (graphStyle == kNetGraphStyleInverseOpposed) {
			if (rxOnTop) {
				[topPath lineToPoint:NSMakePoint(renderPosition, imageSize.height - (rxValue * renderHeight) - 0.5f)];
				[bottomPath lineToPoint:NSMakePoint(renderPosition, (txValue * renderHeight) + 0.5f)];
			} else {
				[topPath lineToPoint:NSMakePoint(renderPosition, imageSize.height - (txValue * renderHeight) - 0.5f)];
				[bottomPath lineToPoint:NSMakePoint(renderPosition, (rxValue * renderHeight) + 0.5f)];
			}
		} else if (graphStyle == kNetGraphStyleOpposed) {
			if (rxOnTop) {
				[topPath lineToPoint:NSMakePoint(renderPosition, imageSize.height - (txValue * renderHeight) - 0.5f)];
				[bottomPath lineToPoint:NSMakePoint(renderPosition, (rxValue * renderHeight) + 0.5f)];
			} else {
				[topPath lineToPoint:NSMakePoint(renderPosition, imageSize.height - (rxValue * renderHeight) - 0.5f)];
				[bottomPath lineToPoint:NSMakePoint(renderPosition, (txValue * renderHeight) + 0.5f)];
			}
		} else if (graphStyle == kNetGraphStyleCentered) {
			if (rxOnTop) {
				[topPath lineToPoint:NSMakePoint(renderPosition, (rxValue * renderHeight) + graphHeight + 1.5f)];
				[bottomPath lineToPoint:NSMakePoint(renderPosition, graphHeight - (txValue * renderHeight) - 0.5f)];
			} else {
				[topPath lineToPoint:NSMakePoint(renderPosition, (txValue * renderHeight) + graphHeight + 1.5f)];
				[bottomPath lineToPoint:NSMakePoint(renderPosition, graphHeight - (rxValue * renderHeight) - 0.5f)];
			}
		} else {
			if (rxOnTop) {
				[topPath lineToPoint:NSMakePoint(renderPosition, (rxValue * renderHeight) + graphHeight + 1.5f)];
				[bottomPath lineToPoint:NSMakePoint(renderPosition, (txValue * renderHeight) + 0.5f)];
			} else {
				[topPath lineToPoint:NSMakePoint(renderPosition, (txValue * renderHeight) + graphHeight + 1.5f)];
				[bottomPath lineToPoint:NSMakePoint(renderPosition, (rxValue * renderHeight) + 0.5f)];
			}
		}
	}

	// Return to lower edge (fill will close the graph)
	if ((graphStyle == kNetGraphStyleOpposed) || (graphStyle == kNetGraphStyleInverseOpposed)) {
		[topPath lineToPoint:NSMakePoint(renderPosition - 1, imageSize.height - 0.5f)];
		[topPath lineToPoint:NSMakePoint(renderPosition - 1, imageSize.height)];
		[bottomPath lineToPoint:NSMakePoint(renderPosition - 1, 0.5f)];
		[bottomPath lineToPoint:NSMakePoint(renderPosition - 1, 0)];
	} else if (graphStyle == kNetGraphStyleCentered) {
		[topPath lineToPoint:NSMakePoint(renderPosition - 1, graphHeight + 1.5f)];
		[topPath lineToPoint:NSMakePoint(renderPosition - 1, graphHeight + 1)];
		[bottomPath lineToPoint:NSMakePoint(renderPosition - 1, graphHeight - 0.5f)];
		[bottomPath lineToPoint:NSMakePoint(renderPosition - 1, graphHeight)];
	} else {
		[topPath lineToPoint:NSMakePoint(renderPosition - 1, graphHeight + 1.5f)];
		[topPath lineToPoint:NSMakePoint(renderPosition - 1, graphHeight + 1)];
		[bottomPath lineToPoint:NSMakePoint(renderPosition - 1, 0.5f)];
		[bottomPath lineToPoint:NSMakePoint(renderPosition - 1, 0)];
	}

	// Draw
	[image lockFocus];
	if (![preferredInterfaceConfig objectForKey:@"interfaceup"]) {
		[inactiveColor set];
		[topPath fill];
		[bottomPath fill];
	} else {
		if (rxOnTop) {
			[rxColor set];
			[topPath fill];
			[txColor set];
			[bottomPath fill];
		} else {
			[rxColor set];
			[bottomPath fill];
			[txColor set];
			[topPath fill];
		}
	}
	[[NSColor blackColor] set];
	[image unlockFocus];

} // renderGraphIntoImage

- (void)renderActivityIntoImage:(NSImage *)image {

	// Get scale (scale is based on latest primary data, not historical)
	float scaleFactor = 0;
	switch ([ourPrefs netScaleMode]) {
		case kNetScaleInterfaceSpeed:
			if ([preferredInterfaceConfig objectForKey:@"speed"]) {
				scaleFactor = [[preferredInterfaceConfig objectForKey:@"speed"] floatValue] / 8;  // Convert to bytes
			}
			break;
		case kNetScalePeakTraffic:
			if (![preferredInterfaceConfig objectForKey:@"statname"]) break;
			if (![netHistoryData count]) break;
			NSDictionary *primaryStats = [[netHistoryData objectAtIndex:0]
										  objectForKey:[preferredInterfaceConfig objectForKey:@"statname"]];
			if (![primaryStats objectForKey:@"peak"]) break;
			scaleFactor = [[primaryStats objectForKey:@"peak"] floatValue];
			break;
	}
	if (scaleFactor > 0) {
		switch ([ourPrefs netScaleCalc]) {
			case kNetScaleCalcLinear:
				// Nothing
				break;
			case kNetScaleCalcSquareRoot:
				scaleFactor = sqrtf(scaleFactor);
				break;
			case kNetScaleCalcCubeRoot:
				scaleFactor = cbrtf(scaleFactor);
				break;
			case kNetScaleCalcLog:
				scaleFactor = logf(scaleFactor);
				break;
		}
	}

	// Get traffic value
	float txValue = 0;
	float rxValue = 0;
	if ([preferredInterfaceConfig objectForKey:@"statname"]) {
		NSDictionary *primaryStats = [[netHistoryData lastObject] objectForKey:[preferredInterfaceConfig objectForKey:@"statname"]];
		NSNumber *sampleIntervalNum = [netHistoryIntervals lastObject];
		if (primaryStats && sampleIntervalNum && ([sampleIntervalNum floatValue] > 0) && (scaleFactor > 0)) {
			txValue = [[primaryStats objectForKey:@"deltaout"] floatValue] / [sampleIntervalNum floatValue];
			rxValue = [[primaryStats objectForKey:@"deltain"] floatValue] / [sampleIntervalNum floatValue];
			switch ([ourPrefs netScaleCalc]) {
				case kNetScaleCalcLinear:
					txValue = txValue / scaleFactor;
					rxValue = rxValue / scaleFactor;
					break;
				case kNetScaleCalcSquareRoot:
					txValue = sqrtf(txValue) / scaleFactor;
					rxValue = sqrtf(rxValue) / scaleFactor;
					break;
				case kNetScaleCalcCubeRoot:
					txValue = cbrtf(txValue) / scaleFactor;
					rxValue = cbrtf(rxValue) / scaleFactor;
					break;
				case kNetScaleCalcLog:
					txValue = logf(txValue) / scaleFactor;
					rxValue = logf(rxValue) / scaleFactor;
					break;
			}
		}
	}
	// Bound
	if (txValue > 1) { txValue = 1; }
	if (rxValue > 1) { rxValue = 1; }
	if (txValue < 0) { txValue = 0;	}
	if (rxValue < 0) { rxValue = 0;	}

	// Lock on image and draw
	[image lockFocus];
	if ([[preferredInterfaceConfig objectForKey:@"interfaceup"] boolValue]) {
		if ([ourPrefs netDisplayOrientation] == kNetDisplayOrientRxTx) {
			[[rxColor colorWithAlphaComponent:rxValue] set];
			[upArrow fill];
			[rxColor set];
			[upArrow stroke];
			[[txColor colorWithAlphaComponent:txValue] set];
			[downArrow fill];
			[txColor set];
			[downArrow stroke];
		} else {
			[[txColor colorWithAlphaComponent:txValue] set];
			[upArrow fill];
			[txColor set];
			[upArrow stroke];
			[[rxColor colorWithAlphaComponent:rxValue] set];
			[downArrow fill];
			[rxColor set];
			[downArrow stroke];
		}
	} else {
		[inactiveColor set];
		[upArrow stroke];
		[downArrow stroke];
	}

	// Reset color and unlock
	[[NSColor blackColor] set];
	[image unlockFocus];

} // renderActivityIntoImage

- (void)renderThroughputIntoImage:(NSImage *)image {

	// Get the primary stats
	double txValue = 0;
	double rxValue = 0;
	if ([[preferredInterfaceConfig objectForKey:@"interfaceup"] boolValue]) {
		NSDictionary *primaryStats = [[netHistoryData lastObject] objectForKey:[preferredInterfaceConfig objectForKey:@"statname"]];
		if (primaryStats) {
			txValue = [[primaryStats objectForKey:@"deltaout"] doubleValue];
			rxValue = [[primaryStats objectForKey:@"deltain"] doubleValue];
		}
	}
	if (txValue < 0) { txValue = 0;	}
	if (rxValue < 0) { rxValue = 0;	}

	// Construct strings
	double sampleInterval = [ourPrefs netInterval];
	NSNumber *sampleIntervalNum = [netHistoryIntervals lastObject];
	if (!sampleIntervalNum && ([sampleIntervalNum doubleValue] > 0)) {
		sampleInterval = [sampleIntervalNum doubleValue];
	}
	NSString *txString = [self menubarThroughputStringForBytes:txValue inInterval:sampleInterval];
	NSString *rxString = [self menubarThroughputStringForBytes:rxValue inInterval:sampleInterval];
	NSAttributedString *renderTxString = [[[NSAttributedString alloc]
												initWithString:txString
													attributes:[NSDictionary dictionaryWithObjectsAndKeys:
																	[NSFont systemFontOfSize:9.5f],
																	NSFontAttributeName,
																	([[preferredInterfaceConfig objectForKey:@"interfaceup"] boolValue] ? txColor : inactiveColor),
																	NSForegroundColorAttributeName,
																	nil]] autorelease];
	NSAttributedString *renderRxString = [[[NSAttributedString alloc]
												initWithString:rxString
													attributes:[NSDictionary dictionaryWithObjectsAndKeys:
																	[NSFont systemFontOfSize:9.5f],
																	NSFontAttributeName,
																	([[preferredInterfaceConfig objectForKey:@"interfaceup"] boolValue] ? rxColor : inactiveColor),
																	NSForegroundColorAttributeName,
																	nil]] autorelease];

	// Draw
	[image lockFocus];
	// Draw label if needed
	float labelOffset = 0;
	if ([ourPrefs netThroughputLabel]) {
		if ([ourPrefs netDisplayMode] & kNetDisplayGraph) {
			labelOffset += [ourPrefs netGraphLength] + kNetDisplayGapWidth;
		}
		if ([ourPrefs netDisplayMode] & kNetDisplayArrows) {
			labelOffset += kNetArrowDisplayWidth + kNetDisplayGapWidth;
		}
		if ([[preferredInterfaceConfig objectForKey:@"interfaceup"] boolValue]) {
			[throughputLabel compositeToPoint:NSMakePoint(labelOffset, 0) operation:NSCompositeSourceOver];
		} else {
			[inactiveThroughputLabel compositeToPoint:NSMakePoint(labelOffset, 0) operation:NSCompositeSourceOver];
		}
	}
	// No descenders, so render lower
	if ([ourPrefs netDisplayOrientation] == kNetDisplayOrientRxTx) {
		[renderRxString drawAtPoint:NSMakePoint((float)ceil(menuWidth - [renderRxString size].width), (float)floor([image size].height / 2) - 1)];
		[renderTxString drawAtPoint:NSMakePoint((float)ceil(menuWidth - [renderTxString size].width), -1)];
	}
	else {
		[renderTxString drawAtPoint:NSMakePoint((float)ceil(menuWidth - [renderTxString size].width), (float)floor([image size].height / 2) - 1)];
		[renderRxString drawAtPoint:NSMakePoint((float)ceil(menuWidth - [renderRxString size].width), -1)];
	}
	[image unlockFocus];

} // renderThroughputIntoImage

///////////////////////////////////////////////////////////////
//
//	Timer callbacks
//
///////////////////////////////////////////////////////////////

- (void)updateNetActivityDisplay:(NSTimer *)timer {

	// Get new config
	[preferredInterfaceConfig release];
	preferredInterfaceConfig = [[netConfig interfaceConfigForInterfaceName:[ourPrefs netPreferInterface]] retain];

	// Get interval for the sample
	NSTimeInterval currentSampleInterval = [ourPrefs netInterval];
	if (lastSampleDate) {
		currentSampleInterval = -[lastSampleDate timeIntervalSinceNow];
	}

	// Load new net data
	NSDictionary *netLoad = [netStats netStatsForInterval:currentSampleInterval];

	// Add to history (at least one)
	if ([ourPrefs netDisplayMode] & kNetDisplayGraph) {
		if ([netHistoryData count] >= [ourPrefs netGraphLength]) {
			[netHistoryData removeObjectsInRange:NSMakeRange(0, [netHistoryData count] - [ourPrefs netGraphLength] + 1)];
		}
		if ([netHistoryIntervals count] >= [ourPrefs netGraphLength]) {
			[netHistoryIntervals removeObjectsInRange:NSMakeRange(0, [netHistoryIntervals count] - [ourPrefs netGraphLength] + 1)];
		}
	} else {
		[netHistoryData removeAllObjects];
		[netHistoryIntervals removeAllObjects];
	}
	[netHistoryData addObject:netLoad];
	[netHistoryIntervals addObject:[NSNumber numberWithDouble:currentSampleInterval]];

	// Update for next sample
	[lastSampleDate release];
	lastSampleDate = [[NSDate date] retain];

	// Force the view to update
	[extraView setNeedsDisplay:YES];

	// If the menu is down force it to update
	if ([self isMenuDown]) {
		[self updateMenuWhenDown];
	}


} // updateNetActivityDisplay

- (void)updateMenuWhenDown {

	// If no menu items are currently live, do nothing
	if (!updateMenuItems) return;

	// Pull in latest data and iterate, updating existing menu items
	NSArray *detailsArray = [netConfig interfaceDetails];
	if (![detailsArray count]) return;
	NSEnumerator *detailsEnum = [detailsArray objectEnumerator];
	NSDictionary *details = nil;
	while ((details = [detailsEnum nextObject])) {
		// Do we have updates?
		if (![details objectForKey:@"service"] || ![updateMenuItems objectForKey:[details objectForKey:@"service"]]) {
			continue;
		}
		NSDictionary *updateInfoForService = [updateMenuItems objectForKey:[details objectForKey:@"service"]];


		// PPP updates
		if ([updateInfoForService objectForKey:@"pppstatusitem"]) {
			NSMenuItem *pppMenuItem = [updateInfoForService objectForKey:@"pppstatusitem"];
			switch ([(NSNumber *)[[details objectForKey:@"pppstatus"] objectForKey:@"status"] unsignedIntValue]) {
				case PPP_IDLE:
					LiveUpdateMenuItemTitle(extraMenu,
											[extraMenu indexOfItem:pppMenuItem],
											[NSString stringWithFormat:kMenuDoubleIndentFormat,
												[localizedStrings objectForKey:kPPPNoConnectTitle]]);
					break;
				case PPP_INITIALIZE:
				case PPP_CONNECTLINK:
				case PPP_STATERESERVED:
				case PPP_ESTABLISH:
				case PPP_AUTHENTICATE:
				case PPP_CALLBACK:
				case PPP_NETWORK:
				case PPP_HOLDOFF:
				case PPP_ONHOLD:
				case PPP_WAITONBUSY:
					LiveUpdateMenuItemTitle(extraMenu,
											[extraMenu indexOfItem:pppMenuItem],
											[NSString stringWithFormat:kMenuDoubleIndentFormat,
												[localizedStrings objectForKey:kPPPConnectingTitle]]);
					break;
				case PPP_RUNNING:
					if ([[details objectForKey:@"pppstatus"] objectForKey:@"timeElapsed"]) {
						uint32_t secs = [[[details objectForKey:@"pppstatus"] objectForKey:@"timeElapsed"] unsignedIntValue];
						uint32_t hours = secs / (60 * 60);
						secs %= (60 * 60);
						uint32_t mins = secs / 60;
						secs %= 60;
						LiveUpdateMenuItemTitle(extraMenu,
												[extraMenu indexOfItem:pppMenuItem],
												[NSString stringWithFormat:kMenuDoubleIndentFormat,
													[NSString stringWithFormat:
														[localizedStrings objectForKey:kPPPConnectedWithTimeTitle],
														hours, mins, secs]]);
					} else {
						LiveUpdateMenuItemTitle(extraMenu,
												[extraMenu indexOfItem:pppMenuItem],
												[NSString stringWithFormat:kMenuDoubleIndentFormat, kPPPConnectedTitle]);
					}
					break;
					break;
				case PPP_TERMINATE:
				case PPP_DISCONNECTLINK:
					LiveUpdateMenuItemTitle(extraMenu,
											[extraMenu indexOfItem:pppMenuItem],
											[NSString stringWithFormat:kMenuDoubleIndentFormat,
												[localizedStrings objectForKey:kPPPDisconnectingTitle]]);
			};
		}
		// Throughput updates
		if ([updateInfoForService objectForKey:@"throughinterface"]) {
			NSNumber *sampleIntervalNum = [netHistoryIntervals lastObject];
			NSDictionary *throughputDetails = [[netHistoryData lastObject] objectForKey:[updateInfoForService objectForKey:@"throughinterface"]];
			if (throughputDetails && sampleIntervalNum) {
				// Update for this interface
				NSMenuItem *targetItem = [updateInfoForService objectForKey:@"deltaoutitem"];
				NSNumber *throughputNumber = [throughputDetails objectForKey:@"deltaout"];
				if (targetItem && throughputNumber) {
					LiveUpdateMenuItemTitle(extraMenu,
											[extraMenu indexOfItem:targetItem],
											[NSString stringWithFormat:kMenuDoubleIndentFormat,
												[NSString stringWithFormat:@"%@ %@",
													[localizedStrings objectForKey:kTxLabel],
													[self throughputStringForBytes:[throughputNumber doubleValue] inInterval:[sampleIntervalNum doubleValue]]]]);
				}
				targetItem = [updateInfoForService objectForKey:@"deltainitem"];
				throughputNumber = [throughputDetails objectForKey:@"deltain"];
				if (targetItem && throughputNumber) {
					LiveUpdateMenuItemTitle(extraMenu,
											[extraMenu indexOfItem:targetItem],
											[NSString stringWithFormat:kMenuDoubleIndentFormat,
												[NSString stringWithFormat:@"%@ %@",
													[localizedStrings objectForKey:kRxLabel],
													[self throughputStringForBytes:[throughputNumber doubleValue] inInterval:[sampleIntervalNum doubleValue]]]]);
				}
				targetItem = [updateInfoForService objectForKey:@"totaloutitem"];
				throughputNumber = [throughputDetails objectForKey:@"totalout"];
				if (targetItem && throughputNumber) {
					LiveUpdateMenuItemTitle(extraMenu,
											[extraMenu indexOfItem:targetItem],
											[NSString stringWithFormat:kMenuDoubleIndentFormat,
												[NSString stringWithFormat:[localizedStrings objectForKey:kTrafficTotalFormat],
													[localizedStrings objectForKey:kTxLabel],
														[self stringForBytes:[throughputNumber doubleValue]],
														[prettyIntFormatter stringForObjectValue:throughputNumber]]]);
				}
				targetItem = [updateInfoForService objectForKey:@"totalinitem"];
				throughputNumber = [throughputDetails objectForKey:@"totalin"];
				if (targetItem && throughputNumber) {
					LiveUpdateMenuItemTitle(extraMenu,
											[extraMenu indexOfItem:targetItem],
											[NSString stringWithFormat:kMenuDoubleIndentFormat,
												[NSString stringWithFormat:[localizedStrings objectForKey:kTrafficTotalFormat],
													[localizedStrings objectForKey:kRxLabel],
													[self stringForBytes:[throughputNumber doubleValue]],
													[prettyIntFormatter stringForObjectValue:throughputNumber]]]);
				}
				targetItem = [updateInfoForService objectForKey:@"peakitem"];
				throughputNumber = [throughputDetails objectForKey:@"peak"];
				if (targetItem && throughputNumber) {
					LiveUpdateMenuItemTitle(extraMenu,
											[extraMenu indexOfItem:targetItem],
											[NSString stringWithFormat:kMenuDoubleIndentFormat,
												[self throughputStringForBPS:[throughputNumber doubleValue]]]);
				}
			}
		}
	} // end details loop

	// Force the menu to redraw
	LiveUpdateMenu(extraMenu);

} // updateMenuWhenDown

///////////////////////////////////////////////////////////////
//
//	Menu actions
//
///////////////////////////////////////////////////////////////

- (void)openNetworkUtil:(id)sender {

	if (![[NSWorkspace sharedWorkspace] launchApplication:@"Network Utility.app"]) {
		NSLog(@"MenuMeterNet unable to launch the Network Utility.");
	}

} // openNetworkUtil

- (void)openNetworkPrefs:(id)sender {

	if (![[NSWorkspace sharedWorkspace] openFile:@"/System/Library/PreferencePanes/Network.prefPane"]) {
		NSLog(@"MenuMeterNet unable to launch the Network Preferences.");
	}

} // openNetworkPrefs

- (void)openInternetConnect:(id)sender {

	if (![[NSWorkspace sharedWorkspace] launchApplication:@"Internet Connect.app"]) {
		NSLog(@"MenuMeterNet unable to launch the Internet Connect application.");
	}

} // openInternetConnect

- (void)switchDisplay:(id)sender {

	NSString *interfaceName = [sender representedObject];
	if (!interfaceName) return;

	// Sanity the name
	NSDictionary *newConfig = [netConfig interfaceConfigForInterfaceName:interfaceName];
	if (!newConfig) return;
	[preferredInterfaceConfig release];
	preferredInterfaceConfig = [newConfig retain];

	// Update prefs
	[ourPrefs saveNetPreferInterface:interfaceName];
	[ourPrefs syncWithDisk];
	// Send the notification to the pref pane
	[[NSDistributedNotificationCenter defaultCenter] postNotificationName:kPrefPaneBundleID
																   object:kPrefChangeNotification];

} // switchDisplay

- (void)copyAddress:(id)sender {

	if ([[sender representedObject] count]) {
		[[NSPasteboard generalPasteboard] declareTypes:[NSArray arrayWithObjects:NSStringPboardType, nil]
												 owner:nil];
		NSString *clipContent = [[sender representedObject] componentsJoinedByString:@", "];
		[[NSPasteboard generalPasteboard] setString:clipContent forType:NSStringPboardType];
	} else {
		NSLog(@"MenuMeterNet unable to copy IP addresses to clipboard.");
	}

} // copyAddress

- (void)pppConnect:(id)sender {

	if ([sender representedObject]) {
		// When we can, use the SC utility function.
		if (isPantherOrLater) {
			// SC connection
			SCNetworkConnectionRef connection = SCNetworkConnectionCreateWithServiceID(
													kCFAllocatorDefault,
													(CFStringRef)[sender representedObject],
													NULL,
													NULL);
			// Undoc preference values
			CFArrayRef connectionOptionList = CFPreferencesCopyValue((CFStringRef)[sender representedObject],
																	 kAppleNetworkConnectDefaultsDomain,
																	 kCFPreferencesCurrentUser,
																	 kCFPreferencesCurrentHost);
			if (connection) {
				if (connectionOptionList && CFArrayGetCount(connectionOptionList)) {
					SCNetworkConnectionStart(connection, CFArrayGetValueAtIndex(connectionOptionList, 0), TRUE);
				} else {
					SCNetworkConnectionStart(connection, NULL, TRUE);
				}
			}
			if (connection) CFRelease(connection);
			if (connectionOptionList) CFRelease(connectionOptionList);
		} else {
			// Direct control for 10.2
			[pppControl connectServiceID:[sender representedObject]];
		}
	}

} // pppConnect

- (void)pppDisconnect:(id)sender {

	if ([sender representedObject]) {
		if (isPantherOrLater) {
			SCNetworkConnectionRef connection = SCNetworkConnectionCreateWithServiceID(
												   kCFAllocatorDefault,
												   (CFStringRef)[sender representedObject],
												   NULL,
												   NULL);
			if (connection) {
				SCNetworkConnectionStop(connection, TRUE);
				CFRelease(connection);
			}
		} else {
			// Direct control for 10.2
			[pppControl disconnectServiceID:[sender representedObject]];
		}
	}

} // pppDisconnect

///////////////////////////////////////////////////////////////
//
//	Pref routines
//
///////////////////////////////////////////////////////////////

- (void)configFromPrefs:(NSNotification *)notification {

	// Update prefs
	[ourPrefs syncWithDisk];

	// Cache colors to skip archiver
	[txColor release];
	txColor = [[ourPrefs netTransmitColor] retain];
	[rxColor release];
	rxColor = [[ourPrefs netReceiveColor] retain];
	[inactiveColor release];
	inactiveColor = [[ourPrefs netInactiveColor] retain];

	// Generate arrow bezier path offset as needed for current display mode
	float arrowOffset =  0;
	float viewHeight = (float)[extraView frame].size.height;
	if ([ourPrefs netDisplayMode] & kNetDisplayGraph) {
		arrowOffset = [ourPrefs netGraphLength] + kNetDisplayGapWidth;
	}
	[upArrow release];
	upArrow = [[NSBezierPath bezierPath] retain];
	[upArrow moveToPoint:NSMakePoint(arrowOffset + (kNetArrowDisplayWidth / 2) + 0.5f, viewHeight - 3.5f)];
	[upArrow lineToPoint:NSMakePoint(arrowOffset + 0.5f, viewHeight - 7.5f)];
	[upArrow lineToPoint:NSMakePoint(arrowOffset + 2.5f, viewHeight - 7.5f)];
	[upArrow lineToPoint:NSMakePoint(arrowOffset + 2.5f, viewHeight - 10.5f)];
	[upArrow lineToPoint:NSMakePoint(arrowOffset + kNetArrowDisplayWidth - 2.5f, viewHeight - 10.5f)];
	[upArrow lineToPoint:NSMakePoint(arrowOffset + kNetArrowDisplayWidth - 2.5f, viewHeight - 7.5f)];
	[upArrow lineToPoint:NSMakePoint(arrowOffset + kNetArrowDisplayWidth - 0.5f, viewHeight - 7.5f)];
	[upArrow closePath];
	[upArrow setLineWidth:0.6f];
	[downArrow release];
	downArrow = [[NSBezierPath bezierPath] retain];
	[downArrow moveToPoint:NSMakePoint(arrowOffset + kNetArrowDisplayWidth / 2 + 0.5f, 2.5f)];
	[downArrow lineToPoint:NSMakePoint(arrowOffset + 0.5f, 6.5f)];
	[downArrow lineToPoint:NSMakePoint(arrowOffset + 2.5f, 6.5f)];
	[downArrow lineToPoint:NSMakePoint(arrowOffset + 2.5f, 9.5f)];
	[downArrow lineToPoint:NSMakePoint(arrowOffset + kNetArrowDisplayWidth - 2.5f, 9.5f)];
	[downArrow lineToPoint:NSMakePoint(arrowOffset + kNetArrowDisplayWidth - 2.5f, 6.5f)];
	[downArrow lineToPoint:NSMakePoint(arrowOffset + kNetArrowDisplayWidth - 0.5f, 6.5f)];
	[downArrow closePath];
	[downArrow setLineWidth:0.6f];

	// Prerender throughput labels
	[throughputLabel release];
	[inactiveThroughputLabel release];
	NSAttributedString *renderTxString = [[[NSAttributedString alloc]
											initWithString:[localizedStrings objectForKey:kTxLabel]
												attributes:[NSDictionary dictionaryWithObjectsAndKeys:
																[NSFont systemFontOfSize:9.5f], NSFontAttributeName,
																txColor, NSForegroundColorAttributeName,
																nil]] autorelease];
	NSAttributedString *renderRxString = [[[NSAttributedString alloc]
											initWithString:[localizedStrings objectForKey:kRxLabel]
												attributes:[NSDictionary dictionaryWithObjectsAndKeys:
																[NSFont systemFontOfSize:9.5f], NSFontAttributeName,
																rxColor, NSForegroundColorAttributeName,
																nil]] autorelease];
	if ([renderTxString size].width > [renderRxString size].width) {
		throughputLabel = [[NSImage alloc] initWithSize:NSMakeSize([renderTxString size].width, viewHeight)];
		inactiveThroughputLabel = [[NSImage alloc] initWithSize:NSMakeSize([renderTxString size].width, viewHeight)];
	} else {
		throughputLabel = [[NSImage alloc] initWithSize:NSMakeSize([renderRxString size].width, viewHeight)];
		inactiveThroughputLabel = [[NSImage alloc] initWithSize:NSMakeSize([renderRxString size].width, viewHeight)];
	}
	[throughputLabel lockFocus];
	// No descenders, render lower
	if ([ourPrefs netDisplayOrientation] == kNetDisplayOrientRxTx) {
		[renderRxString drawAtPoint:NSMakePoint(0, floorf(viewHeight / 2) - 2)];
		[renderTxString drawAtPoint:NSMakePoint(0, -1)];
	} else {
		[renderTxString drawAtPoint:NSMakePoint(0, floorf(viewHeight / 2) - 2)];
		[renderRxString drawAtPoint:NSMakePoint(0, -1)];
	}
	[throughputLabel unlockFocus];
	renderTxString = [[[NSAttributedString alloc]
						initWithString:[localizedStrings objectForKey:kTxLabel]
							attributes:[NSDictionary dictionaryWithObjectsAndKeys:
											[NSFont systemFontOfSize:9.5f], NSFontAttributeName,
											inactiveColor, NSForegroundColorAttributeName,
											nil]] autorelease];
	renderRxString = [[[NSAttributedString alloc]
						initWithString:[localizedStrings objectForKey:kRxLabel]
							attributes:[NSDictionary dictionaryWithObjectsAndKeys:
											[NSFont systemFontOfSize:9.5f], NSFontAttributeName,
											inactiveColor, NSForegroundColorAttributeName,
											nil]] autorelease];
	[inactiveThroughputLabel lockFocus];
	// No descenders, render lower
	if ([ourPrefs netDisplayOrientation] == kNetDisplayOrientRxTx) {
		[renderRxString drawAtPoint:NSMakePoint(0, floorf(viewHeight / 2) - 2)];
		[renderTxString drawAtPoint:NSMakePoint(0, -1)];
	} else {
		[renderTxString drawAtPoint:NSMakePoint(0, floorf(viewHeight / 2) - 2)];
		[renderRxString drawAtPoint:NSMakePoint(0, -1)];
	}
	[inactiveThroughputLabel unlockFocus];

	// Fix our menu view size to match our config
	menuWidth = 0;
	int displayCount = 0;
	if ([ourPrefs netDisplayMode] & kNetDisplayGraph) {
		menuWidth += [ourPrefs netGraphLength];
		displayCount++;
	}
	if ([ourPrefs netDisplayMode] & kNetDisplayArrows) {
		menuWidth += kNetArrowDisplayWidth;
		displayCount++;
	}
	if ([ourPrefs netDisplayMode] & kNetDisplayThroughput) {
		displayCount++;
		if ([ourPrefs netThroughputLabel]) menuWidth += (float)ceil([throughputLabel size].width);
		// Deal with localizable throughput suffix
		float suffixMaxWidth = 0;
		NSAttributedString *throughString = [[[NSAttributedString alloc]
												initWithString:[NSString stringWithFormat:@"99.9%@",
																	[localizedStrings objectForKey:kBytePerSecondLabel]]
													attributes:[NSDictionary dictionaryWithObjectsAndKeys:
																	[NSFont systemFontOfSize:9.5f], NSFontAttributeName,
																	nil]] autorelease];
		if ([throughString size].width > suffixMaxWidth) {
			suffixMaxWidth = (float)[throughString size].width;
		}
		throughString = [[[NSAttributedString alloc]
							initWithString:[NSString stringWithFormat:@"99.9%@",
												[localizedStrings objectForKey:kKBPerSecondLabel]]
								attributes:[NSDictionary dictionaryWithObjectsAndKeys:
												[NSFont systemFontOfSize:9.5f], NSFontAttributeName,
												nil]] autorelease];
		if ([throughString size].width > suffixMaxWidth) {
			suffixMaxWidth = (float)[throughString size].width;
		}
		throughString = [[[NSAttributedString alloc]
							initWithString:[NSString stringWithFormat:@"99.9%@",
												[localizedStrings objectForKey:kMBPerSecondLabel]]
								attributes:[NSDictionary dictionaryWithObjectsAndKeys:
												[NSFont systemFontOfSize:9.5f], NSFontAttributeName,
												nil]] autorelease];
		if ([throughString size].width > suffixMaxWidth) {
			suffixMaxWidth = (float)[throughString size].width;
		}
		throughString = [[[NSAttributedString alloc]
							initWithString:[NSString stringWithFormat:@"99.9%@",
												[localizedStrings objectForKey:kGBPerSecondLabel]]
								attributes:[NSDictionary dictionaryWithObjectsAndKeys:
												[NSFont systemFontOfSize:9.5f], NSFontAttributeName,
												nil]] autorelease];
		if ([throughString size].width > suffixMaxWidth) {
			suffixMaxWidth = (float)[throughString size].width;
		}
		menuWidth += ceilf(suffixMaxWidth) + kNetNumberDisplayGapWidth;
	}
	// If more than one display is present we need to add a gaps
	if (displayCount) {
		menuWidth += ((displayCount - 1) * kNetDisplayGapWidth);
	}

	// Restart the timer
	[updateTimer invalidate];  // Runloop releases and retains the next one
	updateTimer = [NSTimer scheduledTimerWithTimeInterval:[ourPrefs netInterval]
												   target:self
												 selector:@selector(updateNetActivityDisplay:)
												 userInfo:nil
												  repeats:YES];
	// On newer OS versions we need to put the timer into EventTracking to update while the menus are down
	if (isPantherOrLater) {
		[[NSRunLoop currentRunLoop] addTimer:updateTimer
									 forMode:NSEventTrackingRunLoopMode];
	}

	// Resize the view
	[extraView setFrameSize:NSMakeSize(menuWidth, [extraView frame].size.height)];
	[self setLength:menuWidth];

	// Flag us for redisplay
	[extraView setNeedsDisplay:YES];

} // configFromPrefs

///////////////////////////////////////////////////////////////
//
//	Data formatting
//
///////////////////////////////////////////////////////////////

- (NSString *)throughputStringForBPS:(double)bps {

	if ((bps < 1024) && [ourPrefs netThroughput1KBound]) {
		bps = 0;
	}
	if (bps > 1073741824) {
		return [NSString stringWithFormat:@"%@%@",
					[bytesFormatter stringForObjectValue:[NSNumber numberWithDouble:(double)bps / 1073741824]],
					[localizedStrings objectForKey:kGBPerSecondLabel]];
	} else if (bps > 1048576) {
		return [NSString stringWithFormat:@"%@%@",
					[bytesFormatter stringForObjectValue:[NSNumber numberWithDouble:(double)bps / 1048576]],
					[localizedStrings objectForKey:kMBPerSecondLabel]];
	} else if ((bps > 1024) || [ourPrefs netThroughput1KBound]) {
		return [NSString stringWithFormat:@"%@%@",
					[bytesFormatter stringForObjectValue:[NSNumber numberWithDouble:(double)bps / 1024]],
					[localizedStrings objectForKey:kKBPerSecondLabel]];
	} else {
		return [NSString stringWithFormat:@"%.0f%@", (float)bps,
					[localizedStrings objectForKey:kBytePerSecondLabel]];
	}

} // throughputStringForBPS

- (NSString *)throughputStringForBytes:(double)bytes inInterval:(NSTimeInterval)interval {

	if (interval <= 0) return nil;
	return [self throughputStringForBPS:bytes / interval];

} // throughputStringForBytes:inInterval:

- (NSString *)menubarThroughputStringForBytes:(double)bytes inInterval:(NSTimeInterval)interval {

	double bps = bytes / interval;
	if ((bps < 1024) && [ourPrefs netThroughput1KBound]) {
		bps = 0;
	}
	if (bps > 1073741824) {
		return [NSString stringWithFormat:@"%@%@",
				[bytesFormatter stringForObjectValue:[NSNumber numberWithDouble:(double)bps / 1073741824]],
				[localizedStrings objectForKey:kGBPerSecondLabel]];
	} else if (bps > 104857600) {
		// Patch from Alex Eddy, don't show decimals to limit to 4 digits
		return [NSString stringWithFormat:@"%.0f%@", bps / 1048576,
					[localizedStrings objectForKey:kMBPerSecondLabel]];
	} else if (bps > 1048576) {
		return [NSString stringWithFormat:@"%@%@",
				[bytesFormatter stringForObjectValue:[NSNumber numberWithDouble:(double)bps / 1048576]],
				[localizedStrings objectForKey:kMBPerSecondLabel]];
	} else if (bps > 102400) {
		// Patch from Alex Eddy, don't show decimals to limit to 4 digits
		return [NSString stringWithFormat:@"%.0f%@", bps / 1024,
				[localizedStrings objectForKey:kKBPerSecondLabel]];
	} else if ((bps > 1024) || [ourPrefs netThroughput1KBound]) {
		return [NSString stringWithFormat:@"%@%@",
				[bytesFormatter stringForObjectValue:[NSNumber numberWithDouble:(double)bps / 1024]],
				[localizedStrings objectForKey:kKBPerSecondLabel]];
	} else {
		return [NSString stringWithFormat:@"%.0f%@", (float)bps,
				[localizedStrings objectForKey:kBytePerSecondLabel]];
	}

} // menubarThroughputStringForBytes:inInterval:

- (NSString *)stringForBytes:(double)bytes {

	if (bytes > 1073741824) {
		return [NSString stringWithFormat:@"%@%@",
					[bytesFormatter stringForObjectValue:[NSNumber numberWithDouble:bytes / 1073741824]],
					[localizedStrings objectForKey:kGBLabel]];
	} else if (bytes > 1048576) {
		return [NSString stringWithFormat:@"%@%@",
					[bytesFormatter stringForObjectValue:[NSNumber numberWithDouble:bytes / 1048576]],
					[localizedStrings objectForKey:kMBLabel]];
	} else if ((bytes > 1024) || [ourPrefs netThroughput1KBound]) {
		return [NSString stringWithFormat:@"%@%@",
					[bytesFormatter stringForObjectValue:[NSNumber numberWithDouble:bytes / 1024]],
					[localizedStrings objectForKey:kKBLabel]];
	} else {
		return [NSString stringWithFormat:@"%.0f%@", bytes,
					[localizedStrings objectForKey:kByteLabel]];
	}

} // stringForBytes


@end

