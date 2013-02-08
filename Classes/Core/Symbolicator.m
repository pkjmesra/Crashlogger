/*
 Copyright (c) 2011, Praveen K Jha..
 All rights reserved.
 Part of "Open Source" initiative from  Praveen K Jha..
 
 Redistribution and use in source or in binary forms, with or without modification,
 are permitted provided that the following conditions are met:
 
 Redistributions in source or binary form must reproduce the above copyright notice, this
 list of conditions and the following disclaimer in the documentation and/or other
 materials provided with the distribution.
 Neither the name of the Praveen K Jha. nor the names of its contributors may be
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
// See http://www.cocoadev.com/index.pl?StackTraces
/* 1.Xcode's Organizer window: Only works on iPhone crash logs; displays Mac crash logs unchanged
 2.atos  -o path-to-GrowlHelperApp-executable: Does not resolve the symbol; output: “0x00014223”
 3.atos  -o path-to-dSYM-executable: Does not resolve the symbol; output: “0x00014223”
 4.gdb: Requires the main bundle and dSYM bundle to be in the same directory
 This symbolicator is not going to require any dsym file.
 */
#import "Symbolicator.h"
#include <dlfcn.h>

#define kSymbolsProcessStartedMsg   @"Symbolicator --> Symbols are being retained..."
#define kSymbolsProcessCompletedMsg @"Symbolicator --> Symbols have been retained."
#define kSymbolsErrorMsg            @"Symbolicator --> Error while retaining symbols!"
#define kSymbolsDataErrorMsg        @"Symbolicator --> Symbols data error: %@!"

static NSString *HELPSOURCE_CACHE_DIR = @"com.Praveen K Jha.crashreporter.symbols";
static NSString *HELPSOURCE_LIVE_SYMBOLS = @"live_report_symbols.plist";

@implementation Symbolicator

static NSMutableDictionary *symbolDictionary = nil;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+ (NSString *) symbolsDirectory 
{
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSString *mainBundleIdentifier = [mainBundle bundleIdentifier];
    
    NSString *appPath = [mainBundleIdentifier stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cacheDir = [paths objectAtIndex: 0];
    
    return [[cacheDir stringByAppendingPathComponent:HELPSOURCE_CACHE_DIR] stringByAppendingPathComponent:appPath];
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+ (BOOL) populateSymbolsDirectoryAndReturnError:(NSError **)error 
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDictionary *attributes = [NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedLong:0755] 
                                                           forKey:NSFilePosixPermissions];
    
    if (![fileManager fileExistsAtPath:[self symbolsDirectory]] &&
        ![fileManager createDirectoryAtPath:[self symbolsDirectory] withIntermediateDirectories:YES 
                                 attributes:attributes error:error]) {
            return NO;
        }
    
    return YES;
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+ (BOOL) retainSymbolsForStackFrames:(NSArray *)stackFrames inReport:(PLCrashReport *)report {
    NSLog(kSymbolsProcessStartedMsg);
    
    if ([self populateSymbolsDirectoryAndReturnError:NULL]) {
        if (symbolDictionary) {
            [symbolDictionary removeAllObjects];
            [symbolDictionary release];
        }
        symbolDictionary = [[NSMutableDictionary alloc] init];
        
        for (PLCrashReportStackFrameInfo *frameInfo in stackFrames) {
            Dl_info theInfo;
            if ((dladdr((void *)(uintptr_t)frameInfo.instructionPointer, &theInfo) != 0) && theInfo.dli_sname != NULL) {
                NSString *symbol = [NSString stringWithCString:theInfo.dli_sname encoding:NSUTF8StringEncoding];
                NSNumber *pcOffset = 
                [NSNumber numberWithUnsignedInt:(frameInfo.instructionPointer - (uint64_t)theInfo.dli_saddr)];
                [symbolDictionary setObject:[NSArray arrayWithObjects:symbol, pcOffset, nil]
                                     forKey:[NSString stringWithFormat:@"%li",(uintptr_t)frameInfo.instructionPointer]];
            }
        }
        
        NSError *error = nil;
        NSString *plistPath = [[self symbolsDirectory] stringByAppendingPathComponent:HELPSOURCE_LIVE_SYMBOLS];
        NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:symbolDictionary 
                                                                       format:NSPropertyListXMLFormat_v1_0
                                                                      options:0
                                                                        error:&error];
        if (plistData) {
            if ([plistData writeToFile:plistPath atomically:YES]) {
                NSLog(kSymbolsProcessCompletedMsg);
                return YES;
            } else {
                NSLog(kSymbolsErrorMsg);
                return NO;
            }
        } else {
            NSLog(kSymbolsDataErrorMsg, error);
            [error release];
            return NO;
        }
    } else {
        return NO;
    }
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+ (void) clearSymbols {
    [[NSFileManager defaultManager] removeItemAtPath:[self symbolsDirectory] error:NULL];
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+ (NSArray *) symbolAndOffsetForInstructionPointer:(uint64_t)instructionPointer {
    if (!symbolDictionary) {
        NSError *error = nil;
        NSString *plistPath = [[self symbolsDirectory] stringByAppendingPathComponent:HELPSOURCE_LIVE_SYMBOLS];
        
        if (![[NSFileManager defaultManager] fileExistsAtPath:plistPath]) {
            return nil;
        }
        
        NSData *plistXML = [[NSFileManager defaultManager] contentsAtPath:plistPath];
        symbolDictionary = [(NSDictionary *)[NSPropertyListSerialization propertyListWithData:plistXML 
                                                                                      options:NSPropertyListMutableContainersAndLeaves format:NULL error:&error] mutableCopy];
        if (!symbolDictionary) {
            NSLog(@"Error reading plist: %@", error);
        }
    }
    
    if (symbolDictionary) {
        return [symbolDictionary objectForKey:[NSString stringWithFormat:@"%lli", instructionPointer]];
    } else {
        return nil;
    }
}

@end
