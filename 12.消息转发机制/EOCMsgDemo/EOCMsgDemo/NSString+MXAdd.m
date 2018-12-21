//
//  NSString+MXAdd.m
//  EOCMsgDemo
//
//  Created by kuroky on 2018/12/6.
//  Copyright © 2018 Kuroky. All rights reserved.
//

#import "NSString+MXAdd.h"
#import <objc/runtime.h>

@implementation NSString (MXAdd)

+ (void)load {
    // 交换大小写方法
    SEL selector1 = @selector(lowercaseString);
    SEL selector2 = @selector(uppercaseString);
    
    Method method1 = class_getInstanceMethod(self, selector1);
    Method method2 = class_getInstanceMethod(self, selector2);
    
    method_exchangeImplementations(method1, method2);
    
    Method swizzledMethod = class_getInstanceMethod(self, @selector(mx_myCapitalizedString));
    Method originalMethod = class_getInstanceMethod(self, @selector(capitalizedString));
    
    BOOL add = class_addMethod(self, @selector(capitalizedString), method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod)); // 确定当前类是否实现 originalMethod
    if (add) {
        // 当前类没有实现，添加进去再替换
        class_replaceMethod(self, @selector(mx_myCapitalizedString), method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod));
    }
    else {
        // 当前类已经实现 直接交换
        method_exchangeImplementations(swizzledMethod, originalMethod);
    }
    
}

- (NSString *)mx_myCapitalizedString {
    return @"mx_myCapitalizedString";
}

@end
