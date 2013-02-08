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

#import <CrashReporter/CrashReporter.h>

@interface Symbolicator : NSObject

+ (BOOL) retainSymbolsForStackFrames:(NSArray *)stackFrames inReport:(PLCrashReport *)report;
+ (void) clearSymbols;
+ (NSArray *) symbolAndOffsetForInstructionPointer:(uint64_t)instructionPointer;

@end
