//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if defined(__APPLE__)

#import "ObjCExceptionHandling.h"

NSException *_Nullable InvokeBlockCatchingNSExceptionIfThrown(NS_NOESCAPE void(^block)(void)) {
    @try {
        block();
        return nil;
    } @catch (NSException *exception) {
        return exception;
    }
}

#endif
