//
//  DimeloAppDelegate.m
//
//
//  Created by Oleg Andreev on 23.07.2014.
//  Copyright (c) 2014 Dimelo. All rights reserved.
//

#import "DimeloTestAppDelegate.h"
#import "Dimelo/Dimelo.h"
#import "Bugsnag/Bugsnag.h"

NSString* const BUGSNAG_API_KEY = @"41df59ca3b6a42aa9951090a68eac821";

@interface DimeloTestAppDelegate () <DimeloDelegate, UIPopoverControllerDelegate>
@property(nonatomic, readonly) UITabBarController* tabBarController;
@property(nonatomic) UIViewController* tabChatVC;
@property(nonatomic) UIPopoverController* popoverController;

@property(nonatomic) NSTimeInterval unreadFetchInterval;
@property(nonatomic) NSTimer* unreadUpdateTimer;
@end


NSTimeInterval defaultUnreadFetchInterval = 5;


@implementation DimeloTestAppDelegate

#pragma mark - <UIApplicationDelegate>

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // 1. Init with secret and sign internally
    Dimelo* dimelo = [Dimelo sharedInstance];
        
    //! By default, Dimelo is initialized with apiSecret and hostname field of DimeloConfig.plist
    //! But you can override this configuration within the code as follow:
    //! [dimelo setApiKey:@"YOUR_KEY"];
    //! dimelo.hostname = @"YOUR_HOSTNAME";
    dimelo.delegate = self;
    #warning Switch this off when using a distribution provisioning profil
    dimelo.developmentAPNS = YES;
    
    // When any of these properties are set, JWT is recomputed instantly.
    dimelo.userIdentifier = @"U-1000555777";
    dimelo.authenticationInfo = @{@"bankBranch": @"Test-1234" };

    //! Initialize dimelo Chat ViewController
    self.tabChatVC = [dimelo chatViewController];
    self.tabChatVC.tabBarItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"Support", @"Test App") image:[UIImage imageNamed:@"Support"] selectedImage:[UIImage imageNamed:@"SupportSelected"]];

    //! Initialize tabbar controller
    [self.tabBarController addChildViewController:self.tabChatVC];
    [self.tabBarController setSelectedIndex:0];
    [self.tabBarController setSelectedIndex:1];
    [self.tabBarController setSelectedIndex:2];
    [self.tabBarController setSelectedIndex:3];
    [self.tabBarController setSelectedIndex:0];
    
    dimelo.backgroundView.backgroundColor = [UIColor colorWithRed:0.708f green:0.875f blue:0.999f alpha:1.000f];
    self.tabBarController.view.backgroundColor = [UIColor colorWithRed:0.708f green:0.875f blue:0.999f alpha:1.000f];
    
    [dimelo noteUnreadCountDidChange];
    
    //! Handle Notifications
    NSDictionary* dict = launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey];
    if (dict)
    {
        if (![[Dimelo sharedInstance] consumeReceivedRemoteNotification:dict])
        {
            // Handle app-specific notifications...
        }
    }
    
    UILocalNotification* localNotif = launchOptions[UIApplicationLaunchOptionsLocalNotificationKey];
    if (localNotif)
    {
        // We simulate remote notification by putting its payload into a local notification.
        if (![[Dimelo sharedInstance] consumeReceivedRemoteNotification:localNotif.userInfo])
        {
            // Handle app-specific local notifications...
        }
    }
    
    
    self.unreadFetchInterval = defaultUnreadFetchInterval;
    [self updateUnreadCount];

    //Initialize Bugsnag
    BugsnagConfiguration *config = [BugsnagConfiguration new];
    config.apiKey = BUGSNAG_API_KEY;
    // Add Dimelo datas to Bugsnag
    [config addBeforeSendBlock:^bool (NSDictionary *_Nonnull rawEventData, BugsnagCrashReport *report) {
        [report addMetadata:@{@"X-Dimelo-Version": dimelo.sdkVersion} toTabWithName:@"Dimelo"];
        [report addMetadata:@{@"X-Dml-Jwt": dimelo.jwt} toTabWithName:@"Dimelo"];
        [report addMetadata:@{@"X-Dimelo-HostName": dimelo.hostname} toTabWithName:@"Dimelo"];
        return YES;
    }];
    [Bugsnag startBugsnagWithConfiguration:config];

    return YES;
}

// one of these will be called after calling -registerForRemoteNotifications
- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken
{
    // Register the device token.
    [Dimelo sharedInstance].deviceToken = deviceToken;
}

- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error
{
    
}

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo
{
    //! If notification is from Dimelo, you don't have to handle anything
    if ([[Dimelo sharedInstance] consumeReceivedRemoteNotification:userInfo])
        { return; }
    
    //! Otherwise, here you app's handling of this notification.
}

- (void)application:(UIApplication *)application didReceiveLocalNotification:(UILocalNotification *)notification
{
    //! We simulate remote notification by putting its payload into a local notification.
    if ([[Dimelo sharedInstance] consumeReceivedRemoteNotification:notification.userInfo])
        { return; }
    
    //! You app's handling of this notification.
}

- (void)application:(UIApplication*)application handleActionWithIdentifier:(nullable NSString*)identifier forRemoteNotification:(NSDictionary*)userInfo withResponseInfo:(NSDictionary*)responseInfo completionHandler:(void (^) ())completionHandler {

    [[Dimelo sharedInstance] handleRemoteNotificationWithIdentifier: identifier responseInfo: responseInfo];

    if (completionHandler) {

        completionHandler();
    }
}









#pragma mark - <DimeloDelegate>

- (void) dimeloDisplayChatViewController:(Dimelo*)dimelo
{
    UIViewController* vc = [dimelo chatViewController];
    
    vc.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(closeChat:)];
    
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad)
    {
        vc.modalPresentationStyle = UIModalPresentationFormSheet;
    }
    
    [self.tabBarController presentViewController:vc animated:YES completion:^{
       // presented.
    }];
}

- (void) dimeloUnreadCountDidChange:(NSNotification *)notification
{
    [self updateBadgeWithUnreadCount:[Dimelo sharedInstance].unreadCount];
    [self scheduleUnreadCountUpdateTimer];
}

// These callbacks allow you to show and hide network activity indicator.
// If you app uses a stack or counter to manage these, this is the place where you integrate it.
// Dimelo guarantees that dimeloDidEndNetworkActivity is always eventually called after dimeloDidBeginNetworkActivity (whether fails with error or without).
- (void) dimeloDidBeginNetworkActivity:(Dimelo*)dimelo
{
    [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
}

- (void) dimeloDidEndNetworkActivity:(Dimelo*)dimelo
{
    [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
}



#pragma mark - Private

+ (instancetype) sharedInstance
{
    return (DimeloTestAppDelegate*)[UIApplication sharedApplication].delegate;
}

- (UITabBarController*) tabBarController
{
    if ([self.window.rootViewController isKindOfClass:[UITabBarController class]])
    {
        return (id)self.window.rootViewController;
    }
    return nil;
}

- (IBAction) openChat:(id)sender
{
    // Option 1: display chat view using a single delegate method.
    [[Dimelo sharedInstance] displayChatView];
}

- (IBAction) openChatFullScreen:(id)sender
{
    // Option 2: display chat view in a custom manner, not matching one in a delegate.
    
    UIViewController* vc = [[Dimelo sharedInstance] chatViewController];
    
    vc.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(closeChat:)];
    
    vc.modalPresentationStyle = UIModalPresentationFullScreen;
    
    [self.tabBarController presentViewController:vc animated:YES completion:^{
        // presented.
    }];
}

- (IBAction) openChatPopover:(UIButton*)sender
{
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad)
    {
        
        // Option 3: custom presentation (in a popover)
        
        UIViewController* vc = [[Dimelo sharedInstance] chatViewController];
        
        vc.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(closeChat:)];
        
        UIPopoverController* pc = [[UIPopoverController alloc] initWithContentViewController:vc];
        
        pc.contentViewController = vc;
        
        // HACK HACK to fix translucent navbar in popover.
        ((UINavigationController*)vc).navigationBar.backgroundColor = [UIColor colorWithWhite:0.98f alpha:0.95f];
        
        pc.delegate = self;
        //pc.popoverContentSize = CGSizeMake(320, 500);
        [pc presentPopoverFromRect:sender.bounds inView:sender permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
        
        self.popoverController = pc;
    }
    else
    {
        [[[UIAlertView alloc] initWithTitle:@"Only iPad supports popovers, sorry." message:@"" delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
    }
}

- (IBAction) closeChat:(id)sender
{
    if (self.popoverController)
    {
        [self.popoverController dismissPopoverAnimated:YES];
        self.popoverController.delegate = nil;
        self.popoverController = nil;
    }
    else
    {
        [self.tabBarController dismissViewControllerAnimated:YES completion:^{}];
    }
}

- (void)popoverControllerDidDismissPopover:(UIPopoverController *)popoverController
{
    if (self.popoverController)
    {
        self.popoverController.delegate = nil;
        self.popoverController = nil;
    }
}

// Push notifications test

- (IBAction) sendShortMessage:(id)sender
{
    NSArray* messages = @[@"Hi!", @"Hello", @"What's up?", @"Thanks!", @"Kthanxbye", @"Thank you!", @"OMG, REALLY?", @"I don't think so.", @"Maybe tomorrow.", @"How about next Tuesday?", @"This weekend is fine by me.", @"Slightly longer message to be displayed as a non-truncated one."];
    
    NSString* message = messages[dispatch_time(DISPATCH_TIME_NOW, 0) % messages.count];
    
    NSDictionary* notif = @{
                            @"dimelo": @"1.0",
                            @"alert": message,
                            @"badge": @([UIApplication sharedApplication].applicationIconBadgeNumber +
                                (NSInteger)[UIApplication sharedApplication].scheduledLocalNotifications.count +
                                1),
                            @"default_sound": @YES,
                            @"appdata": @{
                                    @"t":    @"m", // notification type = 'message'
                                    @"uuid": [[NSUUID UUID] UUIDString],
                                    @"d":    @([[NSDate date] timeIntervalSince1970]),
                                    @"tr":   @NO,
                                    }
                            };
    
    if (/* DISABLES CODE */ (0))
    {
        // on iOS8 simulator local notif does not work somehow...
        
        UILocalNotification* localNotif = [[UILocalNotification alloc] init];
        localNotif.alertBody = notif[@"alert"];
        localNotif.applicationIconBadgeNumber = [notif[@"badge"] integerValue];
        localNotif.fireDate = [NSDate dateWithTimeIntervalSinceNow:3.0];
        localNotif.userInfo = notif;
        
        [[UIApplication sharedApplication] scheduleLocalNotification:localNotif];
    }
    else
    {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self application:[UIApplication sharedApplication] didReceiveRemoteNotification:notif];
        });
    }
}

- (IBAction) sendLongMessage:(id)sender
{
    NSArray* messages = @[@"In order to activate your account, please follow these simple steps:\n1. Go to www.mybank.example.com.\n2. Click Personal Account.\n3. Find Activate Your Account button on the left of the screen.\n4. Click it and live happily everafter.",
                          @"We are glad to hear from you. One of the available agents will swiftly contact you to respond to your inquiry. Thank you!",
                          @"Unfortunately, time is over. We cannot support this conversation longer. Please leave this chat and try to solve your problem on your own. Thank you for your understanding.",
                          @"This is a rather long message intended to be truncated when displayed on the lock screen. We hope you understand our intention here.",
                          @"Once upon a time there was a little bear-the-pooh who was searching for a pot of honey everywhere."];
    
    NSString* message = messages[dispatch_time(DISPATCH_TIME_NOW, 0) % messages.count];
    
    NSDictionary* notif = @{
                            @"dimelo": @"1.0",
                            @"alert": message,
                            @"badge": @([UIApplication sharedApplication].applicationIconBadgeNumber +
                                (NSInteger)[UIApplication sharedApplication].scheduledLocalNotifications.count +
                                1),
                            @"default_sound": @YES,
                            @"appdata": @{
                                    @"t":    @"m", // notification type = 'message'
                                    @"uuid": [[NSUUID UUID] UUIDString],
                                    @"d":    @([[NSDate date] timeIntervalSince1970]),
                                    @"s":    @[@"a", @"a", @"s"][dispatch_time(DISPATCH_TIME_NOW, 0) % 3],
                                    @"tr":   @YES,
                                    }
                            };
    
    if (/* DISABLES CODE */ (0))
    {
        // on iOS8 simulator local notif does not work somehow...
        
        UILocalNotification* localNotif = [[UILocalNotification alloc] init];
        localNotif.alertBody = notif[@"alert"];
        localNotif.applicationIconBadgeNumber = [notif[@"badge"] integerValue];
        localNotif.fireDate = [NSDate dateWithTimeIntervalSinceNow:3.0];
        localNotif.userInfo = notif;
        
        
        [[UIApplication sharedApplication] scheduleLocalNotification:localNotif];
    }
    else
    {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self application:[UIApplication sharedApplication] didReceiveRemoteNotification:notif];
        });
    }
}

- (void)updateUnreadCount
{
    [self.unreadUpdateTimer invalidate];
    [[Dimelo sharedInstance] fetchUnreadCountWithCompletionHandler:^(NSInteger unreadCount, NSError *error) {
        if (unreadCount == NSNotFound)
        {
            NSLog(@"error while updating unreadCount : %@", error);
            if (error.domain == DimeloHTTPErrorDomain && error.code == 429)
            {
                // 429 Too many requests. Be nice, add some delay.
                self.unreadFetchInterval += defaultUnreadFetchInterval;
            }
        }
        else
        {
            [self updateBadgeWithUnreadCount:unreadCount];
        }
        [self scheduleUnreadCountUpdateTimer];
    }];
}

- (void)updateBadgeWithUnreadCount:(NSInteger)count
{
    self.tabChatVC.tabBarItem.badgeValue = count > 0 ? @(count).stringValue : nil;
}

- (void)scheduleUnreadCountUpdateTimer
{
    [self.unreadUpdateTimer invalidate];
    self.unreadUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:self.unreadFetchInterval target:self selector:@selector(updateUnreadCount) userInfo:nil repeats:NO];
}

@end
