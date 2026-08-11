//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#ifndef ObjCExceptionHandling_h
#define ObjCExceptionHandling_h

#if defined(__APPLE__)

#include <Foundation/NSObjCRuntime.h>
#include <Foundation/NSException.h>

NS_ASSUME_NONNULL_BEGIN

/// Invokes the specified block, catching any `NSException`s that are thrown in the block.
/// - returns: `Nil` if the block didn't throw any exceptions, otherwise the caught exception.
NSException *_Nullable InvokeBlockCatchingNSExceptionIfThrown(NS_NOESCAPE void(^block)(void));

NS_ASSUME_NONNULL_END

#endif
#endif /* ObjCExceptionHandling_h */

