//
//  UITextField+RACSignalSupport.m
//  ReactiveCocoa
//
//  Created by Josh Abernathy on 4/17/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "UITextField+RACSignalSupport.h"
#import "RACSignal.h"
#import "UIControl+RACSignalSupport.h"

@implementation UITextField (RACSignalSupport)

- (RACSignal *)rac_textSubscribable {
	return [[[self rac_subscribableForControlEvents:UIControlEventEditingChanged] startWith:self] map:^(UITextField *x) {
		return x.text;
	}];
}

@end
