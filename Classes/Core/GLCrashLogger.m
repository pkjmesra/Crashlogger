/*
 Copyright (c) 2012, GlobalLogic India Private Limited.
 All rights reserved.
 Part of "Open Source" initiative from iPhone CoE group of GlobalLogic Nagpur.
 
 Redistribution and use in source or in binary forms, with or without modification,
 are permitted provided that the following conditions are met:
 
 Redistributions in source or binary form must reproduce the above copyright notice, this
 list of conditions and the following disclaimer in the documentation and/or other
 materials provided with the distribution.
 Neither the name of the GlobalLogic. nor the names of its contributors may be
 used to endorse or promote products derived from this software without specific
 prior written permission.
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
 OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
 OF THE POSSIBILITY OF SUCH DAMAGE."
 */
/*
 Usage:
 [[GLCrashLogger sharedCrashManager] setSubmissionURL:[NSString stringWithFormat:@"http://107.20.16.199/aurora/fupload?udid=%@&fname=%@%@",@"CrashLogs",[[UIDevice currentDevice].uniqueIdentifier lowercaseString],@"_crashlog.txt"]];
 [GLCrashLogger sharedCrashManager].autoSubmitDeviceUDID =YES;
 [[GLCrashLogger sharedCrashManager] setLoggingEnabled:NO]; // Not required unless you want to debug (in which case set it to YES.By default NO.)
 [[GLCrashLogger sharedCrashManager] setLogCrashThreadStacks:NO]; // Setting to YES would log all threads' stacktrace. By default NO.
 [[GLCrashLogger sharedCrashManager] setDelegate:self];
 [GLCrashLogger sharedCrashManager].autoSubmitCrashReport =YES;
 [GLCrashLogger sharedCrashManager].showAlwaysButton =YES;
 
 */

#import <CrashReporter/CrashReporter.h>
#import <SystemConfiguration/SystemConfiguration.h>
#include <dlfcn.h>
#include <execinfo.h>
#include <sys/sysctl.h>
#include <inttypes.h> //needed for PRIx64 macro

#import <objc/runtime.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
//#import <CoreLocation/CLLocationManager.h>

#import "GLCrashLogger.h"
#import "LFCGzipUtility.h"
#import "Symbolicator.h"
#import "BSReachability.h"
#import "JSONKit.h"

//! Most of the settings could also be loaded from settings bundle [TODO] of 
//! the caller application.
NSBundle *CrashBundleForApp(void) 
{
  static NSBundle* bundle = nil;
  if (!bundle) 
  {
    NSString* path = [[[NSBundle mainBundle] resourcePath]
                      stringByAppendingPathComponent:kCrashBundleName];
    bundle = [[NSBundle bundleWithPath:path] retain];
  }
  return bundle;
}

//! A localizer utility routine
NSString *HSCrashLocalize(NSString *stringToken) 
{
  if ([GLCrashLogger sharedCrashManager].languageStyle == nil)
    return NSLocalizedStringFromTableInBundle(stringToken, @"Crash", CrashBundleForApp(), @"");
  else 
  {
    NSString *alternate = [NSString stringWithFormat:@"Crash%@", 
                           [GLCrashLogger sharedCrashManager].languageStyle];
    return NSLocalizedStringFromTableInBundle(stringToken, alternate, CrashBundleForApp(), @"");
  }
}


@interface GLCrashLogger (Private)

//! Starts the crash manager and sends all crash reports (if any)
- (void)startManager;
//! If the caller needs to display any post-submission resolution data to the user
//! do it here.
- (void)showCrashStatusMessage;
//! Process the available crash reports (if any)
- (void)handleCrashReport;
//! Cleans up the crash reports after processing
- (void)_cleanCrashReports;
//! checks if their is any feedback from the server where the bug/crash was reported
//! [TODO: this could be done using incident notifier]
- (void)_checkForFeedbackStatus;
//! Sends the available crash reports to the server
- (void)_performSendingCrashReports;
//! Sends the available crash reports to the server
- (void)_sendCrashReports;
//! Sends the available crash reports to the server
- (void)_postXML:(NSString*)xml toURL:(NSURL*)url;
//! Device platform
- (NSString *)_getDevicePlatform;

//! checks if we have certain crash reports which we may not have sent yet
- (BOOL)hasNonApprovedCrashReports;
//! checks if we have pending crash reports that need to be sent to developers
- (BOOL)hasPendingCrashReport;

//! returns singleton instance of crashmanager
+ (GLCrashLogger *)sharedCrashManager;
//! callback for plcrashreporter post-crash
void post_crash_callback(siginfo_t *info, ucontext_t *uap, void *context);
//! retains symbols post-crash to report the object names and code-line locations
- (void) retainSymbolsForReport:(PLCrashReport *)report;
//! gets the data in json textual format for reporting the crashed thread's code-location
- (NSData *) DataFromCrashReport:(PLCrashReport *)report;

@end

@implementation GLCrashLogger

@synthesize delegate = _delegate;
@synthesize submissionURL = _submissionURL;
@synthesize showAlwaysButton = _showAlwaysButton;
@synthesize feedbackActivated = _feedbackActivated;
@synthesize autoSubmitCrashReport = _autoSubmitCrashReport;
@synthesize autoSubmitDeviceUDID = _autoSubmitDeviceUDID;
@synthesize languageStyle = _languageStyle;
@synthesize didCrashInLastSession = _didCrashInLastSession;
@synthesize loggingEnabled = _loggingEnabled;
@synthesize logCrashThreadStacks = _logCrashThreadStacks;
@synthesize appIdentifier = _appIdentifier;

PLCrashReport       *_crashReport;

#if __IPHONE_OS_VERSION_MIN_REQUIRED >= 40000
//! returns singleton instance of crashmanager
+(GLCrashLogger *)sharedCrashManager
{   
  static GLCrashLogger *sharedInstance = nil;
  static dispatch_once_t pred;
  
  dispatch_once(&pred, ^{
    sharedInstance = [GLCrashLogger alloc];
    sharedInstance = [sharedInstance init];
  });
  
  return sharedInstance;
}

#else
//! returns singleton instance of crashmanager
+ (GLCrashLogger *)sharedCrashManager {
	static GLCrashLogger *CrashManager = nil;
	
	if (CrashManager == nil) 
    {
		CrashManager = [[GLCrashLogger alloc] init];
	}
	
	return CrashManager;
}

#endif

- (id) init 
{
      if ((self = [super init])) 
      {
        _serverResult = CrashReportStatusUnknown;
        _crashIdenticalCurrentVersion = YES;
        _crashData = nil;
        _urlConnection = nil;
        _submissionURL = nil;
        _responseData = nil;
        _appIdentifier = nil;
        _sendingInProgress = NO;
        _languageStyle = nil;
        _didCrashInLastSession = NO;
        _loggingEnabled = NO;
        _logCrashThreadStacks = NO;

        self.delegate = nil;
        self.feedbackActivated = NO;
        self.showAlwaysButton = NO;
        self.autoSubmitCrashReport = YES;
        self.autoSubmitDeviceUDID = YES;
        
        NSString *testValue = [[NSUserDefaults standardUserDefaults] 
                               stringForKey:kCrashKitAnalyzerStarted];
        if (testValue) 
        {
            _analyzerStarted = [[NSUserDefaults standardUserDefaults] 
                                integerForKey:kCrashKitAnalyzerStarted];
        } else 
        {
            _analyzerStarted = 0;		
        }
        // See if we have any crash reports available at app startup
        testValue = nil;
        testValue = [[NSUserDefaults standardUserDefaults] stringForKey:kCrashKitActivated];
        if (testValue)
        {
            _crashReportActivated = [[NSUserDefaults standardUserDefaults] 
                                     boolForKey:kCrashKitActivated];
        } 
        else 
        {
            _crashReportActivated = YES;
            [[NSUserDefaults standardUserDefaults] 
             setValue:[NSNumber numberWithBool:YES] forKey:kCrashKitActivated];
        }
        
        if (_crashReportActivated) 
        {
            // Get the crash reports
            _crashFiles = [[NSMutableArray alloc] init];
            NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, 
                                                                 NSUserDomainMask, YES);
            _crashesDir = [[NSString stringWithFormat:@"%@", [[paths objectAtIndex:0] stringByAppendingPathComponent:@"/crashes/"]] retain];
            
            NSFileManager *fm = [NSFileManager defaultManager];
            
            NSLog(@"%@",_crashesDir);
            if (![fm fileExistsAtPath:_crashesDir]) 
            {
                // Get the files so we can extract the crash reports
                NSDictionary *attributes = [NSDictionary dictionaryWithObject: [NSNumber numberWithUnsignedLong: 0755] forKey: NSFilePosixPermissions];
                NSError *theError = NULL;
                
                [fm createDirectoryAtPath:_crashesDir 
                    withIntermediateDirectories: YES attributes: attributes error: &theError];
            }
            // Get the crash reporter to work
            PLCrashReporter *crashReporter = [PLCrashReporter sharedReporter];
            NSError *error = NULL;
            // Set the callback that needs to be called when crash happens
            PLCrashReporterCallbacks cb = {
                .version = 0,
                .context = (void *) 0xABABABAB,
                .handleSignal = post_crash_callback
            };
            
            [crashReporter setCrashCallbacks:&cb];
            
            //! Now check if we previously crashed
            // if so, process the crash
            // We do not want to send immediately after crash
            // so the application will send the crash logs for previous crash
            // assuming it does not crash while processing crash logs :)
            if ([crashReporter hasPendingCrashReport] || [self hasPendingCrashReport])
            {
                _didCrashInLastSession = YES;
                [self handleCrashReport];
            }
          
            //! Enable the Crash Reporter
            if (![crashReporter enableCrashReporterAndReturnError: &error])
                NSLog(@"WARNING: Could not enable crash reporter: %@", error);
#ifndef __clang_analyzer__
            // Code not to be analyzed	
            BSReachability *reachability = [[BSReachability reachabilityForInternetConnection] retain]; // Not a leak. It's released after the notification is received
#endif
            [reachability startNotifier];
			// TODO: Potential memory leak. Fix it.
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(startManager) name:HSCrashNetworkBecomeReachable object:nil];
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(networkReachabilityChanged:) name:kReachabilityChangedNotification object:nil];
        }
        
        if (!CrashBundleForApp()) 
        {
            //NSLog(@"WARNING: Crash.bundle is missing, will send reports automatically!");
        }
	}
	return self;
}

//! start manager when internet connection is available
-(void) networkReachabilityChanged: (NSNotification* )note
{
    BSReachability *reachability = (BSReachability *)[note object];
    if ([reachability currentReachabilityStatus] != NotReachable)
    {
        if (_crashReportActivated) 
        {
            [self startManager];
        }
    }
}

- (void) dealloc 
{
    self.delegate = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self 
                                                    name:HSCrashNetworkBecomeReachable 
                                                  object:nil];

    [_languageStyle release];

    [_submissionURL release];
    _submissionURL = nil;

    [_appIdentifier release];
    _appIdentifier = nil;

    [_urlConnection cancel];
    [_urlConnection release]; 
    _urlConnection = nil;

    [_crashData release];

    [_crashesDir release];
    [_crashFiles release];

    [super dealloc];
}


#pragma mark -
#pragma mark setter
//! sets the url where the crash report needs to be submitted
- (void)setSubmissionURL:(NSString *)aSubmissionURL 
{
  if (_submissionURL != aSubmissionURL) 
  {
      [_submissionURL release];
      _submissionURL = [aSubmissionURL copy];
  }
  // We have the submission url.why wait!
  [self performSelector:@selector(startManager) withObject:nil afterDelay:1.0f];
}

//! sets the application unique identifier (com.globallogic.aurora etc.)
- (void)setAppIdentifier:(NSString *)anAppIdentifier 
{    
  if (_appIdentifier != anAppIdentifier) 
  {
    [_appIdentifier release];
    _appIdentifier = [anAppIdentifier copy];
  }
  
  //[self setSubmissionURL:nil];
}


#pragma mark -
#pragma mark private methods
//!sends the crash reports available in the cache automatically without requiring 
//!any input from user
- (BOOL)autoSendCrashReports 
{
  BOOL result = NO;
  // See if we want to take the input from user
  if (!self.autoSubmitCrashReport) 
  {
    if (self.isShowingAlwaysButton && 
        [[NSUserDefaults standardUserDefaults] boolForKey:kAutomaticallySendCrashReports]) 
    {
      result = YES;
    }
  } 
  else 
  {
    result = YES;
  }
  
  return result;
}

//! begin the startup process and send the crash reports to server if we already have the submission url.
- (void)startManager 
{
    // check if we have the crash report or we are already sending
    if (!_sendingInProgress && [self hasPendingCrashReport]) 
    {
        _sendingInProgress = YES;
        
        if (!CrashBundleForApp()) 
        {
            NSLog(@"WARNING: Crash.bundle is missing, sending reports automatically!");
            [self _sendCrashReports];
        }
        // See if the user wants a notification before sending the report
        // and we have crash reports in the cache
        else if (![self autoSendCrashReports] && [self hasNonApprovedCrashReports]) 
        {
            // Show the alert to the user if he/she wants to send the crash report
            if (self.delegate != nil && 
              [self.delegate respondsToSelector:@selector(willShowSubmitCrashReportAlert)]) 
            {
                [self.delegate willShowSubmitCrashReportAlert];
            }
      
            NSString *appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"];
      
            UIAlertView *alertView = [[UIAlertView alloc] 
                          initWithTitle:[NSString stringWithFormat:HSCrashLocalize(@"CrashDataFoundTitle"), appName]
                                message:[NSString stringWithFormat:HSCrashLocalize(@"CrashDataFoundDescription"), appName]
                                delegate:self
                                cancelButtonTitle:HSCrashLocalize(@"CrashDontSendReport")
                                otherButtonTitles:HSCrashLocalize(@"CrashSendReport"), nil];
      
          if ([self isShowingAlwaysButton]) 
          {
              [alertView addButtonWithTitle:HSCrashLocalize(@"CrashSendReportAlways")];
          }
      
          [alertView setTag: CrashKitAlertTypeSend];
          [alertView show];
          [alertView release];
        } 
        else 
        {
            [self _sendCrashReports];
        }
    }
}

//!checks if we have unsent crash reports in the cache
- (BOOL)hasNonApprovedCrashReports {
    NSDictionary *approvedCrashReports = [[NSUserDefaults standardUserDefaults] 
                                          dictionaryForKey: kApprovedCrashReports];
  
    if (!approvedCrashReports || [approvedCrashReports count] == 0) 
      return YES;
  
	for (NSUInteger i=0; i < [_crashFiles count]; i++) 
    {
		NSString *filename = [_crashFiles objectAtIndex:i];
    
        if (![approvedCrashReports objectForKey:filename]) 
            return YES;
    }
  
    return NO;
}

//!checks if we have pending crash reports in the cache
- (BOOL)hasPendingCrashReport 
{
  if (_crashReportActivated) 
  {
    NSFileManager *fm = [NSFileManager defaultManager];
		
    if ([_crashFiles count] == 0 && [fm fileExistsAtPath:_crashesDir]) 
    {
      NSString *file = nil;
      NSError *error = NULL;
		NSLog(@"_crashesDir @ %@",_crashesDir);
      NSDirectoryEnumerator *dirEnum = [fm enumeratorAtPath: _crashesDir];
	
		if (dirEnum != nil)
		{
			// Directory enumeration is going to be faster
			while ((file = [dirEnum nextObject])) 
			{
				NSDictionary *fileAttributes = [fm attributesOfItemAtPath:[_crashesDir stringByAppendingPathComponent:file] error:&error];
				if ([[fileAttributes objectForKey:NSFileSize] intValue] > 0) 
				{
				  [_crashFiles addObject:file];
				}
			}
		}
		else
		{
			// Try the contentsofdirectory method
			NSArray *contents = [fm contentsOfDirectoryAtPath:_crashesDir error:&error];
			for (NSString *file in contents) 
			{
				NSDictionary *fileAttributes = [fm attributesOfItemAtPath:[_crashesDir stringByAppendingPathComponent:file] error:&error];
				if ([[fileAttributes objectForKey:NSFileSize] intValue] > 0) 
				{
					[_crashFiles addObject:file];
				}
			}
		}
    }
    
    if ([_crashFiles count] > 0) 
    {
      NSLog(@"Pending crash reports found.");
      return YES;
    } 
    else
      return NO;
  } 
  else
    return NO;
}

//!shows the crash report submission status
//[TODO: this will need the incident identifier to be checked on server implementation]
- (void) showCrashStatusMessage 
{
	UIAlertView *alertView = nil;
	
	if (_serverResult >= CrashReportStatusAssigned && 
      _crashIdenticalCurrentVersion &&
      CrashBundleForApp()) 
    {
		// show some feedback to the user about the crash status
		NSString *appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"];
		switch (_serverResult) 
        {
			case CrashReportStatusAssigned:
				alertView = [[UIAlertView alloc] initWithTitle: [NSString stringWithFormat:HSCrashLocalize(@"CrashResponseTitle"), appName ]
                                               message: [NSString stringWithFormat:HSCrashLocalize(@"CrashResponseNextRelease"), appName]
                                              delegate: self
                                     cancelButtonTitle: HSCrashLocalize(@"CrashResponseTitleOK")
                                     otherButtonTitles: nil];
				break;
			case CrashReportStatusSubmitted:
				alertView = [[UIAlertView alloc] initWithTitle: [NSString stringWithFormat:HSCrashLocalize(@"CrashResponseTitle"), appName ]
                                               message: [NSString stringWithFormat:HSCrashLocalize(@"CrashResponseWaitingApple"), appName]
                                              delegate: self
                                     cancelButtonTitle: HSCrashLocalize(@"CrashResponseTitleOK")
                                     otherButtonTitles: nil];
				break;
			case CrashReportStatusAvailable:
				alertView = [[UIAlertView alloc] initWithTitle: [NSString stringWithFormat:HSCrashLocalize(@"CrashResponseTitle"), appName ]
                                               message: [NSString stringWithFormat:HSCrashLocalize(@"CrashResponseAvailable"), appName]
                                              delegate: self
                                     cancelButtonTitle: HSCrashLocalize(@"CrashResponseTitleOK")
                                     otherButtonTitles: nil];
				break;
			default:
				alertView = nil;
				break;
		}
		
		if (alertView) 
        {
			[alertView setTag: CrashKitAlertTypeFeedback];
			[alertView show];
			[alertView release];
		}
	}
}


#pragma mark -
#pragma mark UIAlertView Delegate
//! alert view delegate to perform operations based on user choice
- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex 
{
  if ([alertView tag] == CrashKitAlertTypeSend) 
  {
    switch (buttonIndex) 
      {
      case 0:
        _sendingInProgress = NO;
        [self _cleanCrashReports];
        break;
      case 1:
        [self _sendCrashReports];
        break;
      case 2: {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kAutomaticallySendCrashReports];
        [[NSUserDefaults standardUserDefaults] synchronize];
        if (self.delegate != nil && [self.delegate respondsToSelector:@selector(userDidChooseSendAlways)]) 
        {
          [self.delegate userDidChooseSendAlways];
        }
        
        [self _sendCrashReports];
        break;
      }
      default:
        _sendingInProgress = NO;
        [self _cleanCrashReports];
        break;
    }
  }
}

#pragma mark -
#pragma mark NSXMLParser Delegate

#pragma mark NSXMLParser

- (void)parser:(NSXMLParser *)parser 
didStartElement:(NSString *)elementName 
  namespaceURI:(NSString *)namespaceURI 
 qualifiedName:(NSString *)qName 
    attributes:(NSDictionary *)attributeDict 
{
	if (qName) 
    {
		elementName = qName;
	}
	
	if ([elementName isEqualToString:@"result"]) 
    {
		_contentOfProperty = [NSMutableString string];
    }
}

- (void)parser:(NSXMLParser *)parser 
 didEndElement:(NSString *)elementName 
  namespaceURI:(NSString *)namespaceURI 
 qualifiedName:(NSString *)qName 
{
	if (qName) 
    {
		elementName = qName;
	}
	
    // open source implementation
	if ([elementName isEqualToString: @"result"]) 
    {
		if ([_contentOfProperty intValue] > _serverResult) 
        {
			_serverResult = (CrashReportStatus)[_contentOfProperty intValue];
		} 
        else 
        {
            CrashReportStatus errorcode = (CrashReportStatus)[_contentOfProperty intValue];
			NSLog(@"CrashReporter ended in error code: %i", errorcode);
		}
	}
}


- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string 
{
	if (_contentOfProperty) 
    {
		// If the current element is one whose content we care about, append 'string'
		// to the property that holds the content of the current element.
		if (string != nil) 
        {
			[_contentOfProperty appendString:string];
		}
	}
}

#pragma mark -
#pragma mark Private


- (NSString *)_getDevicePlatform 
{
	size_t size = 0;
	sysctlbyname("hw.machine", NULL, &size, NULL, 0);
	char *answer = (char*)malloc(size);
	sysctlbyname("hw.machine", answer, &size, NULL, 0);
	NSString *platform = [NSString stringWithCString:answer encoding: NSUTF8StringEncoding];
	free(answer);
	return platform;
}

- (NSString *)deviceIdentifier 
{
  if ([[UIDevice currentDevice] respondsToSelector:@selector(uniqueIdentifier)]) {
    return [[UIDevice currentDevice] performSelector:@selector(uniqueIdentifier)];
  }
  else {
    return @"invalid";
  }
}

/* If a crash report exists, make it accessible via iTunes document sharing. This is a no-op on Mac OS X. */
-(void) save_crash_report 
{
    //    if (![[PLCrashReporter sharedReporter] hasPendingCrashReport]) 
    //        return;
    
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error;
    
    // Changing to Cache directory to adhere to iCloud guidelines
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory,
                                                         NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    if (![fm createDirectoryAtPath:documentsDirectory withIntermediateDirectories: YES attributes:nil error: &error]) {
        NSLog(@"Could not create documents directory: %@", error);
        return;
    }
    
    NSString * logDirectory =[documentsDirectory stringByAppendingPathComponent:@"logs"];
    if (![fm createDirectoryAtPath: logDirectory withIntermediateDirectories: YES attributes:nil error: &error]) {
        NSLog(@"Could not create logs directory for crash: %@", error);
        return;
    }
    // Prepare the crash report for each thread and registers similar to what xcode does
	for (NSUInteger i=0; i < [_crashFiles count]; i++) 
    {
		NSString *filename = [_crashesDir stringByAppendingPathComponent:[_crashFiles objectAtIndex:i]];
		NSData *crashData = [NSData dataWithContentsOfFile:filename];
		
		if ([crashData length] > 0) 
        {
			PLCrashReport *report = [[[PLCrashReport alloc] initWithData:crashData error:&error] autorelease];
            _crashReport = report;
            if (report == nil) 
            {
                NSLog(@"Could not parse crash report");
                [fm removeItemAtPath:filename error:&error];
                continue;
            }
            else
            {
                NSData *data = [LFCGzipUtility gzipData:[self DataFromCrashReport:_crashReport]];//[[PLCrashReporter sharedReporter] loadPendingCrashReportDataAndReturnError: &error];
                if (data == nil) {
                    NSLog(@"Failed to load crash report data: %@", error);
                    [fm removeItemAtPath:filename error:&error];
                    continue;
                }
                else
                {
                    NSDateFormatter *format = [[NSDateFormatter alloc] init];
                    [format setDateFormat:@"yyyy-MM-dd-HHmmss-ZZZ"];
                    NSDate *now = [NSDate date];
                    NSString *cacheFilename = [format stringFromDate:now];
                    [format release];
                    
                    NSString *outputPath = [logDirectory stringByAppendingPathComponent: [NSString stringWithFormat:@"%@.txt.gz",cacheFilename]];
                    if (![data writeToFile: outputPath atomically: YES]) {
                        NSLog(@"Failed to write crash report");
                    }
                    
                    NSLog(@"Saved crash report to: %@", outputPath);
                    [fm removeItemAtPath:filename error:&error];
                }
            }
		} 
        else 
        {
            // we cannot do anything with this report, so delete it
            [fm removeItemAtPath:filename error:&error];
        }
	}
}

//! start sending the crash reports to the server
- (void)_performSendingCrashReports 
{
    NSMutableDictionary *approvedCrashReports = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] dictionaryForKey: kApprovedCrashReports]];
  
    NSFileManager *fm = [NSFileManager defaultManager];
	NSError *error = NULL;
	
	NSString *userid = @"";
	NSString *contact = @"";
	NSString *description = @"";
  
    if (self.autoSubmitDeviceUDID && [[NSBundle mainBundle] pathForResource:@"embedded" ofType:@"mobileprovision"]) 
    {
        userid = [self deviceIdentifier];
    }
    else if (self.delegate != nil && [self.delegate 
                                      respondsToSelector:@selector(crashReportUserID)])
    {
        userid = [self.delegate crashReportUserID] ?: @"";
    }
	
	if (self.delegate != nil && [self.delegate respondsToSelector:@selector(crashReportContact)]) 
    {
		contact = [self.delegate crashReportContact] ?: @"" ;
	}
	
	if (self.delegate != nil && [self.delegate respondsToSelector:@selector(crashReportDescription)]) 
    {
		description = [self.delegate crashReportDescription] ?: @"";
	}
	
    NSMutableString *crashes = nil;
    _crashIdenticalCurrentVersion = NO;
    // Prepare the crash report for each thread and registers similar to what xcode does
	for (NSUInteger i=0; i < [_crashFiles count]; i++) 
    {
		NSString *filename = [_crashesDir stringByAppendingPathComponent:[_crashFiles objectAtIndex:i]];
		NSData *crashData = [NSData dataWithContentsOfFile:filename];
		
		if ([crashData length] > 0) 
        {
			PLCrashReport *report = [[[PLCrashReport alloc] initWithData:crashData error:&error] autorelease];
            _crashReport = report;
			
            if (report == nil) 
            {
                NSLog(@"Could not parse crash report");
                continue;
            }
            NSLog(@"Crashed on %@", report.systemInfo.timestamp);
            NSLog(@"Crashed with signal %@ (code %@, address=0x%" PRIx64 ")", 
                  report.signalInfo.name,
                  report.signalInfo.code, report.signalInfo.address);

            NSString *crashLogString = [PLCrashReportTextFormatter 
                                        stringValueForCrashReport:report withTextFormat:PLCrashReportTextFormatiOS];
          
            if ([report.applicationInfo.applicationVersion compare:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"]] == NSOrderedSame) {
                _crashIdenticalCurrentVersion = YES;
            }

            if (crashes == nil) 
            {
                crashes = [NSMutableString string];
            }
          
            [crashes appendFormat:@"<crash><applicationname>%s</applicationname><bundleidentifier>%@</bundleidentifier><systemversion>%@</systemversion><platform>%@</platform><senderversion>%@</senderversion><version>%@</version><log><![CDATA[%@]]></log><userid>%@</userid><contact>%@</contact><description><![CDATA[%@]]></description></crash>",
            [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleExecutable"] UTF8String],
            report.applicationInfo.applicationIdentifier,
            report.systemInfo.operatingSystemVersion,
            [self _getDevicePlatform],
            [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"],
            report.applicationInfo.applicationVersion,
            [crashLogString stringByReplacingOccurrencesOfString:@"]]>" withString:@"]]" @"]]><![CDATA[" @">" options:NSLiteralSearch range:NSMakeRange(0,crashLogString.length)],
            userid,
            contact,
                 [description stringByReplacingOccurrencesOfString:@"]]>" withString:@"]]" @"]]><![CDATA[" @">" options:NSLiteralSearch range:NSMakeRange(0,description.length)]];
          
          
            // store this crash report as user approved, so if it fails it will retry automatically
            [approvedCrashReports setObject:[NSNumber numberWithBool:YES] forKey:[_crashFiles objectAtIndex:i]];
		} 
        else 
        {
            // we cannot do anything with this report, so delete it
            [fm removeItemAtPath:filename error:&error];
        }
	}
	
    [[NSUserDefaults standardUserDefaults] setObject:approvedCrashReports forKey:kApprovedCrashReports];
    [[NSUserDefaults standardUserDefaults] synchronize];
    NSDateFormatter *format = [[NSDateFormatter alloc] init];
    [format setDateFormat:@"yyyyMMddHHmmss"];
    NSDate *now = [NSDate date];
    NSString *cacheFilename = [format stringFromDate:now];
    [format release];
    
    if (crashes != nil && [self.submissionURL length]>0)
    {
        NSLog(@"Sending crash reports:\n%@", crashes);
        [self _postXML:[NSString stringWithFormat:@"<crashes>%@</crashes>", crashes]
                 toURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@_%@.txt.gz", 
                                             self.submissionURL,cacheFilename]]];
    
    }
}

//! cleans up the crash report
- (void)_cleanCrashReports 
{
  NSError *error = NULL;
  
  NSFileManager *fm = [NSFileManager defaultManager];
  
  for (NSUInteger i=0; i < [_crashFiles count]; i++) 
  {		
    [fm removeItemAtPath:[_crashesDir stringByAppendingPathComponent:[_crashFiles objectAtIndex:i]] error:&error];
  }
  [_crashFiles removeAllObjects];
  
  [[NSUserDefaults standardUserDefaults] setObject:nil forKey:kApprovedCrashReports];
  [[NSUserDefaults standardUserDefaults] synchronize];    
}

//! sends the crash report to the server
- (void)_sendCrashReports {
    if ([self.submissionURL length] <=0)
        [self save_crash_report];
    else
      // send it to the next runloop
      [self performSelector:@selector(_performSendingCrashReports) withObject:nil afterDelay:0.0f];
}

//!checks for the feedback from server after submitting the crash report
- (void)_checkForFeedbackStatus 
{
    NSMutableURLRequest *request = nil;

    request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@api/2/apps/%@/crashes/%@",
              self.submissionURL,
              [self.appIdentifier stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding],
              _feedbackRequestID
              ]]];

    [request setCachePolicy: NSURLRequestReloadIgnoringLocalCacheData];
    [request setValue:@"Crash/iOS" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"gzip" forHTTPHeaderField:@"Accept-Encoding"];
    [request setTimeoutInterval: 15];
    [request setHTTPMethod:@"GET"];

    _serverResult = CrashReportStatusUnknown;
    _statusCode = 200;

    // Release when done in the delegate method
    _responseData = [[NSMutableData alloc] init];

    if (self.delegate != nil && [self.delegate respondsToSelector:@selector(connectionOpened)]) {
        [self.delegate connectionOpened];
    }

    _urlConnection = [[NSURLConnection alloc] initWithRequest:request delegate:self];    

    NSLog(@"Requesting feedback status.");
}

//! posts crash report to the submission url
- (void)_postXML:(NSString*)xml toURL:(NSURL*)url
{
    NSMutableURLRequest *request = nil;
    NSLog (@"posting data to:%@",[url absoluteString]);
    //  NSString *boundary = @"----Symbolicator";

    if (self.appIdentifier && [self.submissionURL length]>0)
    {
//        request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/%@/crashes",
//                                                                            [self.submissionURL stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding],
//            [self.appIdentifier stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]
//            ]]];
        request = [NSMutableURLRequest requestWithURL:url];
    } 
    else 
    {
        request = [NSMutableURLRequest requestWithURL:url];
    }

    [request setCachePolicy: NSURLRequestReloadIgnoringLocalCacheData];
    [request setValue:@"Crash/iOS" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"gzip" forHTTPHeaderField:@"Accept-Encoding"];
    [request setTimeoutInterval: 15];
    [request setHTTPMethod:@"POST"];
    NSString *contentType = @"application/gzip;";
    //[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
    [request setValue:contentType forHTTPHeaderField:@"Content-type"];

    NSMutableData *postBody =  [NSMutableData data];
    //	[postBody appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    //  if (self.appIdentifier) {
    //    [postBody appendData:[@"Content-Disposition: form-data; name=\"xml\"; filename=\"crash.xml\"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    //    [postBody appendData:[[NSString stringWithFormat:@"Content-Type: text/xml\r\n\r\n"] dataUsingEncoding:NSUTF8StringEncoding]];
    //  } else {
    //    //[postBody appendData:[@"Content-Disposition: form-data; name=\"xmlstring\"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    //	}
    // Include the stack trace for the thread that caused the crash
    [postBody appendData:[self DataFromCrashReport:_crashReport]];
    
    if (self.logCrashThreadStacks)
    {
        // Include all thread states and their stack trace
        [postBody appendData:[xml dataUsingEncoding:NSUTF8StringEncoding]];
    }
    //[postBody appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];

    [request setHTTPBody:[LFCGzipUtility gzipData:postBody]];

    _serverResult = CrashReportStatusUnknown;
    _statusCode = 200;

    //Release when done in the delegate method
    _responseData = [[NSMutableData alloc] init];

    if (self.delegate != nil && 
        [self.delegate respondsToSelector:@selector(connectionOpened)]) 
    {
        [self.delegate connectionOpened];
    }

    [[NSURLCache sharedURLCache] setMemoryCapacity:0];
    [[NSURLCache sharedURLCache] setDiskCapacity:0];
    
    _urlConnection = [[NSURLConnection alloc] initWithRequest:request delegate:self];

    if (!_urlConnection) 
    {
        NSLog(@"Sending crash reports could not start!");
        _sendingInProgress = NO;
    } 
    else 
    {
        NSLog(@"Sending crash reports started.");
    }
}

#pragma mark NSURLConnection Delegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response 
{
	if ([response isKindOfClass:[NSHTTPURLResponse class]]) 
    {
		_statusCode = [(NSHTTPURLResponse *)response statusCode];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data 
{
	[_responseData appendData:data];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error 
{
    [_responseData release];
    _responseData = nil;
    _urlConnection = nil;
	
    if (self.delegate != nil && [self.delegate respondsToSelector:@selector(connectionClosed)]) 
    {
        [self.delegate connectionClosed];
    }
    NSLog (@"[error localizedDescription]:%@",[error localizedDescription]);
    NSLog(@"ERROR: %@", [error localizedDescription]);
  
    _sendingInProgress = NO;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)connectionDidFinishLoading:(NSURLConnection *)connection 
{
        if (_statusCode >= 200 && 
          _statusCode < 400 && 
          _responseData != nil && 
          [_responseData length] > 0) 
        {
            [self _cleanCrashReports];
            [Symbolicator clearSymbols];
          
            _feedbackRequestID = nil;
//            if (self.appIdentifier) 
//            {
//              //use PList XML format
//              NSMutableDictionary *response = 
//                    [NSPropertyListSerialization propertyListFromData:_responseData
//                               mutabilityOption:NSPropertyListMutableContainersAndLeaves
//                                         format:nil
//                               errorDescription:NULL];
//              NSLog(@"Received API response: %@", response);
//              
//              _serverResult = (CrashReportStatus)[[response objectForKey:@"status"] intValue];
//              if ([response objectForKey:@"id"]) 
//              {
//                _feedbackRequestID = [[NSString alloc] initWithString:[response objectForKey:@"id"]];
//                _feedbackDelayInterval = [[response objectForKey:@"delay"] floatValue];
//                if (_feedbackDelayInterval > 0)
//                  _feedbackDelayInterval *= 0.01;
//              }
//            } 
//            else 
            {
                NSLog(@"Received API response: %@", [[[NSString alloc] initWithBytes:[_responseData bytes] length:[_responseData length] encoding: NSUTF8StringEncoding] autorelease]);
          
              NSXMLParser *parser = [[NSXMLParser alloc] initWithData:_responseData];
              // Set self as the delegate of the parser so that it will receive the parser delegate methods callbacks.
              [parser setDelegate:self];
              // Depending on the XML document you're parsing, you may want to enable these features of NSXMLParser.
              [parser setShouldProcessNamespaces:NO];
              [parser setShouldReportNamespacePrefixes:NO];
              [parser setShouldResolveExternalEntities:NO];
              
              [parser parse];
              
              [parser release];
            }
    
            if ([self isFeedbackActivated]) 
            {
                  // only proceed if the server did not report any problem
                  if ((self.appIdentifier) && (_serverResult == CrashReportStatusQueued)) 
                  {
                    // the report is still in the queue
                    if (_feedbackRequestID) 
                    {
                      [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_checkForFeedbackStatus) object:nil];
                      [self performSelector:@selector(_checkForFeedbackStatus) withObject:nil afterDelay:_feedbackDelayInterval];
                    }
                  } 
                  else 
                  {
                    [self showCrashStatusMessage];
                  }
            }
        } 
        else 
        {
            if (_responseData == nil || [_responseData length] == 0) 
            {
                NSLog(@"ERROR: Sending failed with an empty response!");
            } 
            else 
            {
                NSLog(@"ERROR: Sending failed with status code: %i", _statusCode);
            }
        }
	
      [_responseData release];
      _responseData = nil;
      _urlConnection = nil;
	
      if (self.delegate != nil && [self.delegate respondsToSelector:@selector(connectionClosed)]) 
      {
        [self.delegate connectionClosed];
      }
  
    _sendingInProgress = NO;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (PLCrashReport *) crashReport 
{
    if (!_crashReport) 
    {
        NSError *error = nil;
        
        NSData *crashData = [[PLCrashReporter sharedReporter] loadPendingCrashReportDataAndReturnError:&error];
        if (!crashData) 
        {

            [[PLCrashReporter sharedReporter] purgePendingCrashReport];
            return nil;
        }
        
        _crashReport = [[PLCrashReport alloc] initWithData:crashData error:&error];
        if (!_crashReport) 
        {
            [[PLCrashReporter sharedReporter] purgePendingCrashReport];
            return nil;
        } 
        else 
        {
            return _crashReport;
        }
    } 
    else 
    {
        return _crashReport;
    }
}

#pragma mark PLCrashReporter
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//
// Called to handle a pending crash report.
//
- (void) handleCrashReport 
{
	PLCrashReporter *crashReporter = [PLCrashReporter sharedReporter];
	NSError *error = NULL;
	
  // check if the next call ran successfully the last time
	if (_analyzerStarted == 0) 
    {
		// mark the start of the routine
		_analyzerStarted = 1;
		[[NSUserDefaults standardUserDefaults] setValue:[NSNumber numberWithInt:_analyzerStarted] forKey:kCrashKitAnalyzerStarted];
		[[NSUserDefaults standardUserDefaults] synchronize];
    
        // Try loading the crash report
        _crashData = [[NSData alloc] initWithData:[crashReporter loadPendingCrashReportDataAndReturnError: &error]];
    
        NSString *cacheFilename = [NSString stringWithFormat: @"%.0f", [NSDate timeIntervalSinceReferenceDate]];
        NSLog(@"crashesDir:%@ and filename:%@",_crashesDir,cacheFilename);
        if (_crashData == nil) 
        {
          NSLog(@"Could not load crash report: %@", error);
        } 
        else 
        {
          [_crashData writeToFile:[_crashesDir stringByAppendingPathComponent: cacheFilename] atomically:YES];
        }
	}

        // Purge the report
        // mark the end of the routine
        _analyzerStarted = 0;
        [[NSUserDefaults standardUserDefaults] setValue:[NSNumber numberWithInt:_analyzerStarted] forKey:kCrashKitAnalyzerStarted];
      [[NSUserDefaults standardUserDefaults] synchronize];
  
    if ([self hasPendingCrashReport])
        [self save_crash_report];
	[crashReporter purgePendingCrashReport];
	return;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (void) retainSymbolsForReport:(PLCrashReport *)report 
{
	NSLog(@"In retainSymbolsForReport after crashing"); // See in organizer console
    PLCrashReportThreadInfo *crashedThreadInfo = nil;
    for (PLCrashReportThreadInfo *threadInfo in report.threads) 
    {
        if (threadInfo.crashed) 
        {
            crashedThreadInfo = threadInfo;
            break;
        }
    }
    
    if (!crashedThreadInfo) 
    {
        if (report.threads.count > 0) 
        {
            crashedThreadInfo = [report.threads objectAtIndex:0];
        }
    }
    
    if (report.hasExceptionInfo) 
    {
        PLCrashReportExceptionInfo *exceptionInfo = report.exceptionInfo;
        [Symbolicator retainSymbolsForStackFrames:exceptionInfo.stackFrames inReport:report];
    } 
    else
    {
        [Symbolicator retainSymbolsForStackFrames:crashedThreadInfo.stackFrames inReport:report];
    }
    if ([self hasPendingCrashReport])
        [self save_crash_report];
}


#pragma mark - Crash callback function
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
void post_crash_callback(siginfo_t *info, ucontext_t *uap, void *context) 
{
    [[GLCrashLogger sharedCrashManager] performSelectorOnMainThread:@selector(retainSymbolsForReport:) 
                                             withObject:[[GLCrashLogger sharedCrashManager] crashReport] 
                                          waitUntilDone:YES];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (NSData *) DataFromCrashReport:(PLCrashReport *)report 
{
    if (!report) 
    {
        return nil;
    }
    
    @try 
    {
        
        // --application_environment
        NSMutableDictionary *application_environment = [[NSMutableDictionary alloc] init];
        
        // ----appname
        NSArray *identifierComponents = [report.applicationInfo.applicationIdentifier componentsSeparatedByString:@"."];
        if (identifierComponents && identifierComponents.count > 0) 
        {
            [application_environment setObject:[identifierComponents lastObject] forKey:@"appname"];
        }
        
        // ----appver
        CFBundleRef bundle = CFBundleGetBundleWithIdentifier((CFStringRef)report.applicationInfo.applicationIdentifier);
        CFDictionaryRef bundleInfoDict = CFBundleGetInfoDictionary(bundle);
        CFStringRef buildNumber;
        
        // If we succeeded, look for our property.
        if (bundleInfoDict != NULL) 
        {
            buildNumber = CFDictionaryGetValue(bundleInfoDict, CFSTR("CFBundleShortVersionString"));
            if (buildNumber) 
            {
                [application_environment setObject:(NSString *)buildNumber forKey:@"appver"];
            }
        }
        
        // ----internal_version
        [application_environment setObject:report.applicationInfo.applicationVersion forKey:@"internal_version"];
        
//        // ----gps_on
//        [application_environment setObject:[NSNumber numberWithBool:[CLLocationManager locationServicesEnabled]] 
//                                    forKey:@"gps_on"];
        
        if (bundleInfoDict != NULL) 
        {
            NSMutableString *languages = [[NSMutableString alloc] init];
            CFStringRef baseLanguage = CFDictionaryGetValue(bundleInfoDict, kCFBundleDevelopmentRegionKey);
            if (baseLanguage) 
            {
                [languages appendString:(NSString *)baseLanguage];
            }
            
            CFStringRef allLanguages = CFDictionaryGetValue(bundleInfoDict, kCFBundleLocalizationsKey);
            if (allLanguages) 
            {
                [languages appendString:(NSString *)allLanguages];
            }
            if (languages) 
            {
                [application_environment setObject:(NSString *)languages forKey:@"languages"];
            }
            [languages release];
        }
        
        // ----locale
        [application_environment setObject:[[NSLocale currentLocale] localeIdentifier] forKey:@"locale"];
        
        // ----mobile_net_on, wifi_on
        BSReachability *reach = [BSReachability reachabilityForInternetConnection];
        NetworkStatus status = [reach currentReachabilityStatus];
        switch (status) 
        {
            case NotReachable:
                [application_environment setObject:[NSNumber numberWithBool:NO] forKey:@"mobile_net_on"];
                [application_environment setObject:[NSNumber numberWithBool:NO] forKey:@"wifi_on"];
                break;
            case ReachableViaWiFi:
                [application_environment setObject:[NSNumber numberWithBool:NO] forKey:@"mobile_net_on"];
                [application_environment setObject:[NSNumber numberWithBool:YES] forKey:@"wifi_on"];
                break;
            case ReachableViaWWAN:
                [application_environment setObject:[NSNumber numberWithBool:YES] forKey:@"mobile_net_on"];
                [application_environment setObject:[NSNumber numberWithBool:NO] forKey:@"wifi_on"];
                break;
        }
        
        // ----osver
        [application_environment setObject:report.systemInfo.operatingSystemVersion forKey:@"osver"];
        
        // ----timestamp
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"YYYY-MM-dd HH:mm:ss zzzzz"];
        [application_environment setObject:[formatter stringFromDate:report.systemInfo.timestamp] 
                                    forKey:@"timestamp"];
        [formatter release];
        
        
        // --exception
        NSMutableDictionary *exception = [[[NSMutableDictionary alloc] init] autorelease];
        
        // ----backtrace, where
        PLCrashReportThreadInfo *crashedThreadInfo = nil;
        for (PLCrashReportThreadInfo *threadInfo in report.threads)
        {
            if (threadInfo.crashed) 
            {
                crashedThreadInfo = threadInfo;
                break;
            }
        }
        
        if (!crashedThreadInfo) 
        {
            if (report.threads.count > 0)
            {
                crashedThreadInfo = [report.threads objectAtIndex:0];
            }
        }
        // stack trace
        NSMutableArray *stacktrace = [[NSMutableArray alloc] init];
        if (report.hasExceptionInfo) 
        {
            PLCrashReportExceptionInfo *exceptionInfo = report.exceptionInfo;
            NSInteger pos = -1;
            
            for (NSUInteger frameIndex = 0; frameIndex < [exceptionInfo.stackFrames count]; frameIndex++) 
            {
                PLCrashReportStackFrameInfo *frameInfo = [exceptionInfo.stackFrames objectAtIndex:frameIndex];
                PLCrashReportBinaryImageInfo *imageInfo;
                
                uint64_t baseAddress = 0x0;
                uint64_t pcOffset = 0x0;
                const char *imageName = "\?\?\?";
                //image info
                imageInfo = [report imageForAddress:frameInfo.instructionPointer];
                if (imageInfo != nil) 
                {
                    imageName = [[imageInfo.imageName lastPathComponent] UTF8String];
                    baseAddress = imageInfo.imageBaseAddress;
                    pcOffset = frameInfo.instructionPointer - imageInfo.imageBaseAddress;
                }
                
                //Dl_info theInfo;
                NSString *stackframe = nil;
                NSString *commandName = nil;
                // get details on what crashed the app-- exactly which instruction
                NSArray *symbolAndOffset = 
                [Symbolicator symbolAndOffsetForInstructionPointer:frameInfo.instructionPointer];
                if (symbolAndOffset && symbolAndOffset.count > 1) 
                {
                    commandName = [symbolAndOffset objectAtIndex:0];
                    pcOffset = ((NSString *)[symbolAndOffset objectAtIndex:1]).integerValue;
                    stackframe = [NSString stringWithFormat:@"%-4ld%-36s0x%08" PRIx64 " %@ + %" PRId64 "",
                                  (long)frameIndex, imageName, frameInfo.instructionPointer, commandName, pcOffset];
                } 
                else 
                {
                    stackframe = [NSString stringWithFormat:@"%-4ld%-36s0x%08" PRIx64 " 0x%" PRIx64 " + %" PRId64 "", 
                                  (long)frameIndex, imageName, frameInfo.instructionPointer, baseAddress, pcOffset];
                }
                
                [stacktrace addObject:stackframe];
                
                if ([commandName hasPrefix:@"+[NSException raise:"])
                {
                    pos = frameIndex+1;
                } 
                else 
                {
                    if (pos != -1 && pos == frameIndex) 
                    {
                        [exception setObject:stackframe forKey:@"where"];
                    }
                }
            }
        } 
        else 
        {
            for (NSUInteger frameIndex = 0; frameIndex < [crashedThreadInfo.stackFrames count]; frameIndex++) 
            {
                PLCrashReportStackFrameInfo *frameInfo = [crashedThreadInfo.stackFrames objectAtIndex:frameIndex];
                PLCrashReportBinaryImageInfo *imageInfo;
                
                uint64_t baseAddress = 0x0;
                uint64_t pcOffset = 0x0;
                const char *imageName = "\?\?\?";
                
                imageInfo = [report imageForAddress:frameInfo.instructionPointer];
                if (imageInfo != nil) 
                {
                    imageName = [[imageInfo.imageName lastPathComponent] UTF8String];
                    baseAddress = imageInfo.imageBaseAddress;
                    pcOffset = frameInfo.instructionPointer - imageInfo.imageBaseAddress;
                }
                
                //Dl_info theInfo;
                NSString *stackframe = nil;
                NSString *commandName = nil;
                NSArray *symbolAndOffset = 
                [Symbolicator symbolAndOffsetForInstructionPointer:frameInfo.instructionPointer];
                if (symbolAndOffset && symbolAndOffset.count > 1) 
                {
                    commandName = [symbolAndOffset objectAtIndex:0];
                    pcOffset = ((NSString *)[symbolAndOffset objectAtIndex:1]).integerValue;
                    stackframe = [NSString stringWithFormat:@"%-4ld%-36s0x%08" PRIx64 " %@ + %" PRId64 "",
                                  (long)frameIndex, imageName, frameInfo.instructionPointer, commandName, pcOffset];
                } 
                else 
                {
                    stackframe = [NSString stringWithFormat:@"%-4ld%-36s0x%08" PRIx64 " 0x%" PRIx64 " + %" PRId64 "", 
                                  (long)frameIndex, imageName, frameInfo.instructionPointer, baseAddress, pcOffset];
                }
                [stacktrace addObject:stackframe];
                
                if (report.signalInfo.address == frameInfo.instructionPointer) 
                {
                    [exception setObject:stackframe forKey:@"where"];
                }
            }
        }
        
        if (![exception objectForKey:@"where"] && stacktrace && stacktrace.count > 0) 
        {
            [exception setObject:[stacktrace objectAtIndex:0] forKey:@"where"];
        }
        
        if (stacktrace.count > 0) 
        {
            [exception setObject:stacktrace forKey:@"backtrace"];
        } 
        else 
        {
            [exception setObject:@"No backtrace available [?]" forKey:@"backtrace"];
        }
        [stacktrace release];
        // ----klass, message
        if (report.hasExceptionInfo) 
        {
            [exception setObject:report.exceptionInfo.exceptionName forKey:@"klass"];
            [exception setObject:report.exceptionInfo.exceptionReason forKey:@"message"];
        } 
        else 
        {
            [exception setObject:@"SIGNAL" forKey:@"klass"];
            [exception setObject:report.signalInfo.name forKey:@"message"];
        }
        
        // --request
        NSMutableDictionary *request = [[[NSMutableDictionary alloc] init] autorelease];
        
        // root
        NSMutableDictionary *rootDictionary = [[[NSMutableDictionary alloc] init] autorelease];
        [rootDictionary setObject:application_environment forKey:@"application_environment"];
        [rootDictionary setObject:exception forKey:@"exception"];
        [rootDictionary setObject:request forKey:@"request"];
        [application_environment release];
        NSString *jsonString;
        if ([rootDictionary respondsToSelector:@selector(JSONString)])
        {
            jsonString = [[rootDictionary JSONString] stringByReplacingOccurrencesOfString:@",\"" withString:@",\"\r\n"];
        }
        else if([rootDictionary respondsToSelector:@selector(JSONRepresentation)])
        {
            NSString * json = [rootDictionary performSelector:@selector(JSONRepresentation)];
            jsonString = jsonString = [json stringByReplacingOccurrencesOfString:@",\"" withString:@",\"\r\n"];
        }
        
        NSLog(@"CrashReport at:%@ GMT\n:%@",[NSDate date],jsonString);
        NSLog(@"#######################################################################################################");
        NSLog(@"########################## Application crashed. CrashReport ########################################\n:%@",jsonString);
        NSLog(@"#######################################################################################################");
        return [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    } 
    @catch (NSException *exception) 
    {
        return nil;
    }
}

@end
