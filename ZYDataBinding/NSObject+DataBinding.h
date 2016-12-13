//
//  NSObject+DataBinding.h
//  ZYDataBinding
//
//  Created by zhangyun on 13/12/2016.
//  Copyright © 2016 zhangyun. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ZYDBMacro.h"

// 用来处理返回值得
typedef id (^ZYDBKeyBindingTransform)(id value);

@interface NSObject (DataBinding)

- (void)zy_addTarget:(id)target action:(SEL)action forkeyPathChange:(NSString *)keyPath;

@end
