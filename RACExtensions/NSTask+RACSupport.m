//
//  NSTask+RACSupport.m
//  ReactiveCocoa
//
//  Created by Josh Abernathy on 5/10/12.
//  Copyright (c) 2012 GitHub. All rights reserved.
//

#import "NSTask+RACSupport.h"
#import "NSFileHandle+RACSupport.h"
#import "NSNotificationCenter+RACSupport.h"

NSString * const NSTaskRACSupportErrorDomain = @"NSTaskRACSupportErrorDomain";

NSString * const NSTaskRACSupportOutputData = @"NSTaskRACSupportOutputData";
NSString * const NSTaskRACSupportErrorData = @"NSTaskRACSupportErrorData";
NSString * const NSTaskRACSupportTask = @"NSTaskRACSupportTask";
NSString * const NSTaskRACSupportOutputString = @"NSTaskRACSupportOutputString";
NSString * const NSTaskRACSupportErrorString = @"NSTaskRACSupportErrorString";
NSString * const NSTaskRACSupportTaskArguments = @"NSTaskRACSupportTaskArguments";

const NSInteger NSTaskRACSupportNonZeroTerminationStatus = 123456;


@implementation NSTask (RACSupport)

- (RACSignal *)rac_standardOutputSubscribable {
	if(![[self standardOutput] isKindOfClass:[NSPipe class]]) {
		[self setStandardOutput:[NSPipe pipe]];
	}
	
	return [self rac_subscribableForPipe:[self standardOutput]];
}

- (RACSignal *)rac_standardErrorSubscribable {
	if(![[self standardError] isKindOfClass:[NSPipe class]]) {
		[self setStandardError:[NSPipe pipe]];
	}
	
	return [self rac_subscribableForPipe:[self standardError]];
}

- (RACSignal *)rac_subscribableForPipe:(NSPipe *)pipe {
	NSFileHandle *fileHandle = [pipe fileHandleForReading];	
	return [fileHandle rac_readInBackground];
}

- (RACSignal *)rac_completionSubscribable {
	return [[[NSNotificationCenter.defaultCenter rac_addObserverForName:NSTaskDidTerminateNotification object:self] any] mapReplace:RACUnit.defaultUnit];
}

- (RACCancelableSignal *)rac_run {
	return [self rac_runWithScheduler:[RACScheduler immediateScheduler]];
}

- (RACCancelableSignal *)rac_runWithScheduler:(RACScheduler *)scheduler {
	NSParameterAssert(scheduler != nil);
	
	RACAsyncSubject *subject = [RACAsyncSubject subject];
	
	__block BOOL canceled = NO;
	[[RACScheduler mainQueueScheduler] schedule:^{
		NSMutableData * (^aggregateData)(NSMutableData *, NSData *) = ^(NSMutableData *running, NSData *next) {
			[running appendData:next];
			return running;
		};
		
		// TODO: should we aggregate the data on the given scheduler too?
		RACConnectableSignal *outputSubscribable = [[[self rac_standardOutputSubscribable] aggregateWithStart:[NSMutableData data] combine:aggregateData] publish];
		__block NSData *outputData = nil;
		[outputSubscribable subscribeNext:^(NSData *accumulatedData) {
			outputData = accumulatedData;
		}];
		
		RACConnectableSignal *errorSubscribable = [[[self rac_standardErrorSubscribable] aggregateWithStart:[NSMutableData data] combine:aggregateData] publish];
		__block NSData *errorData = nil;
		[errorSubscribable subscribeNext:^(NSData *accumulatedData) {
			errorData = accumulatedData;
		}];
				
		// wait until termination's signaled and output and error are done
		[[RACSignal merge:[NSArray arrayWithObjects:outputSubscribable, errorSubscribable, [self rac_completionSubscribable], nil]] subscribeNext:^(id _) {
			// nothing
		} completed:^{
			if(canceled) return;
						
			[scheduler schedule:^{
				if(canceled) return;
								
				if([self terminationStatus] == 0) {
					[subject sendNext:outputData];
					[subject sendCompleted];
				} else {
					NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
					if(outputData != nil) {
						[userInfo setObject:outputData forKey:NSTaskRACSupportOutputData];
						
						NSString *string = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
						if(string != nil) [userInfo setObject:string forKey:NSTaskRACSupportOutputString];
					}
					if(errorData != nil) {
						[userInfo setObject:errorData forKey:NSTaskRACSupportErrorData];
						
						NSString *string = [[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding];
						if(string != nil) [userInfo setObject:string forKey:NSTaskRACSupportErrorString];
					}
					if([self arguments] != nil) [userInfo setObject:[self arguments] forKey:NSTaskRACSupportTaskArguments];
					[userInfo setObject:self forKey:NSTaskRACSupportTask];
					[subject sendError:[NSError errorWithDomain:NSTaskRACSupportErrorDomain code:NSTaskRACSupportNonZeroTerminationStatus userInfo:userInfo]];
				}
			}];
		}];
		
		[outputSubscribable connect];
		[errorSubscribable connect];
		
		[self launch];
	}];
	
	__weak NSTask *weakSelf = self;
	return [subject asCancelableWithBlock:^{
		NSTask *strongSelf = weakSelf;
		canceled = YES;
		[strongSelf terminate];
	}];
}

@end
