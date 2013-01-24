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
 Build instructions:
 
 1. You may have to add crashReporter.framework (PLCrashReporter) into your main application.
 2. Also add libz.dylib as a linked library.
 3. Add the "$(BUILD_DIR)/$(CONFIGURATION)$(EFFECTIVE_PLATFORM_NAME)/usr/local/include/" into the
    header search path because GLCrashLogger.h (this file) will be dumped there as a result of
    building this static library. Alternatively, you could add this header file separately into your
    main application.
 4. You should also have a JOSNKit that either supports JSONString or JSONRepresentation
    for NSDictionary returning NSString. Choose any framework or jsonkit you like and add
    that into your main application.
 
 Usage:
 [[GLCrashLogger sharedCrashManager] setSubmissionURL:[NSString stringWithFormat:@"http://107.20.16.199/aurora/fupload?udid=%@&fname=%@%@",@"CrashLogs",[[UIDevice currentDevice].uniqueIdentifier lowercaseString],@"_crashlog.txt"]];
 [GLCrashLogger sharedCrashManager].autoSubmitDeviceUDID =YES;
 [[GLCrashLogger sharedCrashManager] setLoggingEnabled:NO]; // Not required unless you want to debug (in which case set it to YES.By default NO.)
 [[GLCrashLogger sharedCrashManager] setLogCrashThreadStacks:NO]; // Setting to YES would log all threads' stacktrace. By default NO.
 [[GLCrashLogger sharedCrashManager] setDelegate:self];
 [GLCrashLogger sharedCrashManager].autoSubmitCrashReport =YES;
 [GLCrashLogger sharedCrashManager].showAlwaysButton =YES;
 
 */
#import <Foundation/Foundation.h>

#define HSCrashLog(fmt, ...) do { if([GLCrashLogger sharedCrashManager].isLoggingEnabled) { NSLog((@"[CrashLib] %s/%d " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__); }} while(0)

#define kCrashBundleName @"Crash.bundle"

NSBundle *CrashBundleForApp(void);
NSString *HSCrashLocalize(NSString *stringToken);

//!#define HSCrashLocalize(StringToken) NSLocalizedStringFromTableInBundle(StringToken, @"Crash", CrashBundleForApp(), @"")

//! flags if the crashlog analyzer is started. since this may theoretically crash we need to track it
#define kCrashKitAnalyzerStarted @"CrashKitAnalyzerStarted"

//! flags if the CrashKit is activated at all
#define kCrashKitActivated @"CrashKitActivated"

//! flags if the crashreporter should automatically send crashes without asking the user again
#define kAutomaticallySendCrashReports @"AutomaticallySendCrashReports"

//! stores the set of crashreports that have been approved but aren't sent yet
#define kApprovedCrashReports @"ApprovedCrashReports"

//! Notification message which CrashManager is listening to, to retry sending pending crash reports to the server
#define HSCrashNetworkBecomeReachable @"NetworkDidBecomeReachable"

typedef enum CrashKitAlertType {
	CrashKitAlertTypeSend = 0,
	CrashKitAlertTypeFeedback = 1,
} CrashAlertType;

typedef enum CrashReportStatus {
  //! The status of the crash is queued, need to check later (HockeyApp)
	CrashReportStatusQueued = -80,
  
  //! This app version is set to discontinued, no new crash reports accepted by the server
	CrashReportStatusFailureVersionDiscontinued = -30,
  
  //! XML: Sender version string contains not allowed characters, only alphanumberical including space and . are allowed
	CrashReportStatusFailureXMLSenderVersionNotAllowed = -21,
  
  //! XML: Version string contains not allowed characters, only alphanumberical including space and . are allowed
	CrashReportStatusFailureXMLVersionNotAllowed = -20,
  
  //! SQL for adding a symoblicate todo entry in the database failed
	CrashReportStatusFailureSQLAddSymbolicateTodo = -18,
  
  //! SQL for adding crash log in the database failed
	CrashReportStatusFailureSQLAddCrashlog = -17,
  
  //! SQL for adding a new version in the database failed
	CrashReportStatusFailureSQLAddVersion = -16,
	
  //! SQL for checking if the version is already added in the database failed
  CrashReportStatusFailureSQLCheckVersionExists = -15,
	
  //! SQL for creating a new pattern for this bug and set amount of occurrances to 1 in the database failed
  CrashReportStatusFailureSQLAddPattern = -14,
	
  //! SQL for checking the status of the bugfix version in the database failed
  CrashReportStatusFailureSQLCheckBugfixStatus = -13,
	
  //! SQL for updating the occurances of this pattern in the database failed
  CrashReportStatusFailureSQLUpdatePatternOccurances = -12,
	
  //! SQL for getting all the known bug patterns for the current app version in the database failed
  CrashReportStatusFailureSQLFindKnownPatterns = -11,
	
  //! SQL for finding the bundle identifier in the database failed
  CrashReportStatusFailureSQLSearchAppName = -10,
	
  //! the post request didn't contain valid data
  CrashReportStatusFailureInvalidPostData = -3,
	
  //! incoming data may not be added, because e.g. bundle identifier wasn't found
  CrashReportStatusFailureInvalidIncomingData = -2,
	
  //! database cannot be accessed, check hostname, username, password and database name settings in config.php
  CrashReportStatusFailureDatabaseNotAvailable = -1,
	
  CrashReportStatusUnknown = 0,
	
  CrashReportStatusAssigned = 1,
	
  CrashReportStatusSubmitted = 2,
	
  CrashReportStatusAvailable = 3,
} CrashReportStatus;

//! This protocol is used to send the image updates
@protocol GLCrashLoggerDelegate <NSObject>

@optional

//! Return the userid the crashreport should contain, empty by default
-(NSString *) crashReportUserID;

//! Return the contact value (e.g. email) the crashreport should contain, empty by default
-(NSString *) crashReportContact;

//! Return the description the crashreport should contain, empty by default. The string will automatically be wrapped into <[DATA[ ]]>, so make sure you don't do that in your string.
-(NSString *) crashReportDescription;

//! Invoked when the internet connection is started, to let the app enable the activity indicator
-(void) connectionOpened;

//! Invoked when the internet connection is closed, to let the app disable the activity indicator
-(void) connectionClosed;

//! Invoked before the user is asked to send a crash report, so you can do additional actions. E.g. to make sure not to ask the user for an app rating :) 
-(void) willShowSubmitCrashReportAlert;

//! Invoked after the user did choose to send crashes always in the alert 
-(void) userDidChooseSendAlways;

@end

@interface GLCrashLogger : NSObject <NSXMLParserDelegate> 
{
        NSString *_submissionURL;

        id <GLCrashLoggerDelegate> _delegate;

        BOOL _loggingEnabled;
        BOOL _logCrashThreadStacks;
        BOOL _showAlwaysButton;
        BOOL _feedbackActivated;
        BOOL _autoSubmitCrashReport;
        BOOL _autoSubmitDeviceUDID;

        BOOL _didCrashInLastSession;

        NSString *_appIdentifier;

        NSString *_feedbackRequestID;
        float _feedbackDelayInterval;

        NSMutableString *_contentOfProperty;
        CrashReportStatus _serverResult;

        int _analyzerStarted;
        NSString *_crashesDir;

        BOOL _crashIdenticalCurrentVersion;
        BOOL _crashReportActivated;

        NSMutableArray *_crashFiles;

        NSMutableData *_responseData;
        NSInteger _statusCode;

        NSURLConnection *_urlConnection;

        NSData *_crashData;

        NSString *_languageStyle;
        BOOL _sendingInProgress;
}

+ (GLCrashLogger *)sharedCrashManager;

//! submission URL defines where to send the crash reports to (required)
@property (nonatomic, retain) NSString *submissionURL;

//! delegate is optional
@property (nonatomic, assign) id <GLCrashLoggerDelegate> delegate;

///////////////////////////////////////////////////////////////////////////////////////////////////
// settings

//! if YES, states will be logged using NSLog. Only enable this for debugging!
//! if NO, nothing will be logged. (default)
@property (nonatomic, assign, getter=isLoggingEnabled) BOOL loggingEnabled;

//! if YES, all threads and their stack information will be part of crash log. Only enable this for debugging!
//! if NO, only crash thread srash will be logged. (default)
@property (nonatomic, assign) BOOL logCrashThreadStacks;

//! nil, using the default localization files (Default)
//! set to another string which will be appended to the Crash localization file name, "Alternate" is another provided text set
@property (nonatomic, retain) NSString *languageStyle;

//! if YES, the user will get the option to choose "Always" for sending crash reports. This will cause the dialog not to show the alert description text landscape mode! (default)
//! if NO, the dialog will not show a "Always" button
@property (nonatomic, assign, getter=isShowingAlwaysButton) BOOL showAlwaysButton;

//! if YES, the user will be presented with a status of the crash, if known
//! if NO, the user will not see any feedback information (default)
@property (nonatomic, assign, getter=isFeedbackActivated) BOOL feedbackActivated;

//! if YES, the crash report will be submitted without asking the user
//! if NO, the user will be asked if the crash report can be submitted (default)
@property (nonatomic, assign, getter=isAutoSubmitCrashReport) BOOL autoSubmitCrashReport;

//! if YES, the device UDID will be submitted as the user id, without the need to define it in the crashReportUserID delegate (meant for beta versions!)
//! if NO, the crashReportUserID delegate defines what to be sent as user id (default)
@property (nonatomic, assign, getter=isAutoSubmitDeviceUDID) BOOL autoSubmitDeviceUDID;

//! will return if the last session crashed, to e.g. make sure a "rate my app" alert will not show up
@property (nonatomic, readonly) BOOL didCrashInLastSession;

//! set your unique app identifier
@property (nonatomic, retain) NSString *appIdentifier;

@end
