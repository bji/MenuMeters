//
//  MenuMeterWorkarounds.m
//
//	Various workarounds for old OS bugs that may not be applicable
//  (or compilable) on newer OS versions. To prevent conflicts
//  everything here is __private_extern__.
//
//	Copyright (c) 2009-2012 Alex Harper
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

#import "MenuMeterWorkarounds.h"
#import "AppleUndocumented.h"


__private_extern__ void LiveUpdateMenuItemTitle(NSMenu *menu, CFIndex index, NSString *title) {

	// Update a menu itm various displays. Under 10.4 the Carbon and Cocoa menus
	// were not kept in sync. This problem disappeared later (not a problem in
	// 10.5). Since x86_64 can't call Carbon we have to wrap this in our
	// own call.

	// Guard against < 1 based values (such as the output of [NSMenu indexOfItem:]
	// when the item is not found.
	if (index < 0) return;

#if MAC_OS_X_VERSION_MIN_REQUIRED <= MAC_OS_X_VERSION_10_4
	// The Carbon side is set first since setting it results in a empty
	// title on the Cocoa side.
	MenuRef carbonMenu = _NSGetCarbonMenu(menu);
	if (carbonMenu) {
		SetMenuItemTextWithCFString(carbonMenu,
									index + 1,  // Carbon menus 1-based index
									(CFStringRef)title);
	}
#endif
	[[menu itemAtIndex:index] setTitle:title];

} // LiveUpdateMenuItemTitle

__private_extern__ void LiveUpdateMenu(NSMenu *menu) {

#if MAC_OS_X_VERSION_MIN_REQUIRED <= MAC_OS_X_VERSION_10_4
	MenuRef carbonMenu = _NSGetCarbonMenu(menu);
	if (carbonMenu) {
		UpdateInvalidMenuItems(carbonMenu);
	}
#endif

} // LiveUpdateMenu
