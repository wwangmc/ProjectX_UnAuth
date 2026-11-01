#import <CoreLocation/CoreLocation.h>
#import <MapKit/MapKit.h>
#import <Contacts/Contacts.h>
#import "PXHookSupport.h"

static NSDictionary *PXLocationConfig(void) { return PXRuntime()[@"location"]; }
static CLLocation *PXLocation(void) {
    NSDictionary *d=PXLocationConfig();
    if (!d) return nil;
    return [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake([d[@"latitude"] doubleValue],[d[@"longitude"] doubleValue])
        altitude:[d[@"altitude"] doubleValue] horizontalAccuracy:d[@"horizontalAccuracy"]?[d[@"horizontalAccuracy"] doubleValue]:5
        verticalAccuracy:d[@"verticalAccuracy"]?[d[@"verticalAccuracy"] doubleValue]:5
        course:d[@"course"]?[d[@"course"] doubleValue]:-1 speed:d[@"speed"]?[d[@"speed"] doubleValue]:-1 timestamp:NSDate.date];
}
static void PXDidUpdateLocations(id self, SEL cmd, CLLocationManager *manager, NSArray *locations) {
    CLLocation *location=PXLocation();
    IMP original=PXOriginalMethod(self,cmd);
    if (original) ((void(*)(id,SEL,id,id))original)(self,cmd,manager,location?@[location]:locations);
}
%hook CLLocationManager
- (void)setDelegate:(id)delegate {
    if (delegate) PXInstallMethod(object_getClass(delegate),@selector(locationManager:didUpdateLocations:),
        (IMP)PXDidUpdateLocations,"v",4);
    %orig(delegate);
}
- (CLLocation *)location { return PXLocation() ?: %orig; }
%end

%hook CLLocation
- (CLLocationCoordinate2D)coordinate {
    NSDictionary *d=PXLocationConfig();
    return d?CLLocationCoordinate2DMake([d[@"latitude"] doubleValue],[d[@"longitude"] doubleValue]):%orig;
}
- (CLLocationDistance)altitude { id n=PXLocationConfig()[@"altitude"]; return n?[n doubleValue]:%orig; }
- (CLLocationAccuracy)horizontalAccuracy { return PXLocationConfig() ? [PXLocationConfig()[@"horizontalAccuracy"] ?: @5 doubleValue] : %orig; }
- (CLLocationAccuracy)verticalAccuracy { return PXLocationConfig() ? [PXLocationConfig()[@"verticalAccuracy"] ?: @5 doubleValue] : %orig; }
- (CLLocationSpeed)speed { id n=PXLocationConfig()[@"speed"]; return n?[n doubleValue]:%orig; }
- (CLLocationDirection)course { id n=PXLocationConfig()[@"course"]; return n?[n doubleValue]:%orig; }
%end

%hook CLPlacemark
- (CLLocation *)location { return PXLocation() ?: %orig; }
- (NSString *)name { return PXLocationConfig()[@"name"] ?: %orig; }
- (NSString *)thoroughfare { return PXLocationConfig()[@"thoroughfare"] ?: %orig; }
- (NSString *)subThoroughfare { return PXLocationConfig()[@"subThoroughfare"] ?: %orig; }
- (NSString *)locality { return PXLocationConfig()[@"locality"] ?: %orig; }
- (NSString *)subLocality { return PXLocationConfig()[@"subLocality"] ?: %orig; }
- (NSString *)administrativeArea { return PXLocationConfig()[@"administrativeArea"] ?: %orig; }
- (NSString *)postalCode { return PXLocationConfig()[@"postalCode"] ?: %orig; }
- (NSString *)country { return PXLocationConfig()[@"country"] ?: %orig; }
- (NSString *)ISOcountryCode { return PXLocationConfig()[@"ISOcountryCode"] ?: %orig; }
- (CLRegion *)region {
    CLLocation *l=PXLocation();
    return l?[[CLCircularRegion alloc] initWithCenter:l.coordinate radius:50 identifier:@"ProjectX"]:%orig;
}
- (NSArray *)areasOfInterest { NSDictionary *d=PXLocationConfig(); return d?(d[@"name"]?@[d[@"name"]]:@[]):%orig; }
- (CNPostalAddress *)postalAddress {
    NSDictionary *d=PXLocationConfig();
    if (!d) return %orig;
    CNMutablePostalAddress *a=[CNMutablePostalAddress new];
    a.street=[@[d[@"thoroughfare"] ?: @"",d[@"subThoroughfare"] ?: @""] componentsJoinedByString:@" "];
    a.city=d[@"locality"] ?: @""; a.subLocality=d[@"subLocality"] ?: @"";
    a.state=d[@"administrativeArea"] ?: @""; a.postalCode=d[@"postalCode"] ?: @"";
    a.country=d[@"country"] ?: @""; a.ISOCountryCode=d[@"ISOcountryCode"] ?: @"";
    return a;
}
%end

%hook CLGeocoder
- (void)reverseGeocodeLocation:(CLLocation *)location completionHandler:(CLGeocodeCompletionHandler)completion {
    CLLocation *replacement=PXLocation();
    if (!replacement || !completion) { %orig; return; }
    NSDictionary *d=PXLocationConfig();
    NSDictionary *address=@{@"Name":d[@"name"] ?: @"",@"City":d[@"locality"] ?: @"",
        @"Country":d[@"country"] ?: @"",@"CountryCode":d[@"ISOcountryCode"] ?: @"",
        @"Street":d[@"thoroughfare"] ?: @"",@"ZIP":d[@"postalCode"] ?: @""};
    MKPlacemark *place=[[MKPlacemark alloc] initWithCoordinate:replacement.coordinate addressDictionary:address];
    dispatch_async(dispatch_get_main_queue(), ^{ completion(@[place],nil); });
}
%end

%hook CLLocationSourceInformation
- (BOOL)isSimulatedBySoftware { return PXRuntimeFlag(@"hideSimulatedLocation")?NO:%orig; }
- (BOOL)isProducedByAccessory { return PXRuntimeFlag(@"hideSimulatedLocation")?NO:%orig; }
%end

%ctor { %init; }
