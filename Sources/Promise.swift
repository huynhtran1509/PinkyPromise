//
//  Promise.swift
//  PinkyPromise
//
//  Created by Kevin Conner on 3/16/16.
//
//  The MIT License (MIT)
//  Copyright © 2016 WillowTree, Inc. All rights reserved.
// 
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to
//  deal in the Software without restriction, including without limitation the
//  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
//  sell copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
//  DEALINGS IN THE SOFTWARE.
//

import Foundation

// A task that can resolve to a value or an error asynchronously.

// First, create a Promise, or use firstly() for neatness.
// Use .flatMap to chain additional monadic tasks. Failures skip over mapped tasks.
// Use .success or .failure to process a success or failure value, then continue.
// After building up your composite promise, begin it with .call.
// Use the result enum directly, or call .value() to unwrap it and have failures thrown.

public struct Promise<T> {

    public typealias Value = T
    public typealias Observer = (Result<Value>) -> Void
    public typealias Task = (Observer) -> Void

    private let task: Task

    // A promise that produces its result by running an asynchronous task.
    public init(task: Task) {
        self.task = task
    }

    // A promise that trivially produces a result.
    public init(result: Result<Value>) {
        self.init { fulfill in
            fulfill(result)
        }
    }

    // A promise that trivially succeeds.
    public init(value: Value) {
        self.init(result: .Success(value))
    }

    // A promise that trivially fails.
    public init(error: ErrorType) {
        self.init(result: .Failure(error))
    }

    // MARK: Promise transformations

    // Produces a composite promise that resolves by calling this promise, then transforming its success value.
    public func map<U>(transform: (Value) throws -> U) -> Promise<U> {
        return flatMap { value in
            let mappedValue = try transform(value)
            return Promise<U>(value: mappedValue)
        }
    }

    // Produces a composite promise that resolves by calling this promise, passing its result to the next task,
    // then calling the produced promise.
    public func flatMap<U>(transform: (Value) throws -> Promise<U>) -> Promise<U> {
        return Promise<U> { fulfill in
            self.call { result in
                do {
                    let value = try result.value()
                    let mappedPromise = try transform(value)
                    mappedPromise.call(fulfill)
                } catch {
                    fulfill(.Failure(error))
                }
            }
        }
    }

    // Produces a composite promise that resolves by calling this promise, then the next, and if successful combines
    // their results in the produced promise.
    // This is a like zip() in that you want multiple results, but the first step must complete before beginning the second step.
    public func flatMapAndJoin<U>(transform: (Value) throws -> Promise<U>) -> Promise<(Value, U)> {
        return flatMap { value1 in
            let mappedPromise = try transform(value1)
            return mappedPromise.map { (value2) -> (Value, U) in
                return (value1, value2)
            }
        }
    }

    // Produces a composite promise that resolves by running this promise in the background queue,
    // then fulfills on the main queue.
    public func background() -> Promise<Value> {
        return Promise { fulfill in
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
                self.task { result in
                    dispatch_async(dispatch_get_main_queue()) {
                        fulfill(result)
                    }
                }
            }
        }
    }

    // MARK: Result delivery

    // Produces a composite promise that resolves by calling this promise, but also performs another task if successful.
    public func success(successTask: (Value) -> Void) -> Promise<Value> {
        return Promise { fulfill in
            self.call { result in
                if case .Success(let value) = result {
                    successTask(value)
                }
                fulfill(result)
            }
        }
    }

    // Produces a composite promise that resolves by calling this promise, but also performs another task if failed.
    public func failure(failureTask: (ErrorType) -> Void) -> Promise<Value> {
        return Promise { fulfill in
            self.call { result in
                if case .Failure(let error) = result {
                    failureTask(error)
                }
                fulfill(result)
            }
        }
    }

    // Performs work defined by the promise and eventually calls completion.
    // Promises won't do any work until you call this.
    public func call(completion: Observer?) {
        task { result in
            completion?(result)
        }
    }

}

// Immediately runs a closure to lift regular code into Promise context.
public func firstly<T>(@noescape firstTask: () -> Promise<T>) -> Promise<T> {
    return firstTask()
}

// Produces a promise that runs two promises simultaneously and unifies their result.
public func zip<A, B>(promiseA: Promise<A>, _ promiseB: Promise<B>) -> Promise<(A, B)> {
    return Promise { fulfill in
        let group = dispatch_group_create()

        var resultA: Result<A>!
        var resultB: Result<B>!

        dispatch_group_enter(group)
        promiseA.call { result in
            resultA = result
            dispatch_group_leave(group)
        }

        dispatch_group_enter(group)
        promiseB.call { result in
            resultB = result
            dispatch_group_leave(group)
        }

        dispatch_group_notify(group, dispatch_get_main_queue()) {
            fulfill(zip(resultA, resultB))
        }
    }
}

// Produces a promise that runs three promises simultaneously and unifies their result.
public func zip<A, B, C>(promiseA: Promise<A>, _ promiseB: Promise<B>, _ promiseC: Promise<C>) -> Promise<(A, B, C)> {
    return Promise { fulfill in
        let group = dispatch_group_create()

        var resultA: Result<A>!
        var resultB: Result<B>!
        var resultC: Result<C>!

        dispatch_group_enter(group)
        promiseA.call { result in
            resultA = result
            dispatch_group_leave(group)
        }

        dispatch_group_enter(group)
        promiseB.call { result in
            resultB = result
            dispatch_group_leave(group)
        }

        dispatch_group_enter(group)
        promiseC.call { result in
            resultC = result
            dispatch_group_leave(group)
        }

        dispatch_group_notify(group, dispatch_get_main_queue()) {
            fulfill(zip(resultA, resultB, resultC))
        }
    }
}

// Produces a promise that runs four promises simultaneously and unifies their result.
public func zip<A, B, C, D>(promiseA: Promise<A>, _ promiseB: Promise<B>, _ promiseC: Promise<C>, _ promiseD: Promise<D>) -> Promise<(A, B, C, D)> {
    return Promise { fulfill in
        let group = dispatch_group_create()

        var resultA: Result<A>!
        var resultB: Result<B>!
        var resultC: Result<C>!
        var resultD: Result<D>!

        dispatch_group_enter(group)
        promiseA.call { result in
            resultA = result
            dispatch_group_leave(group)
        }

        dispatch_group_enter(group)
        promiseB.call { result in
            resultB = result
            dispatch_group_leave(group)
        }

        dispatch_group_enter(group)
        promiseC.call { result in
            resultC = result
            dispatch_group_leave(group)
        }

        dispatch_group_enter(group)
        promiseD.call { result in
            resultD = result
            dispatch_group_leave(group)
        }

        dispatch_group_notify(group, dispatch_get_main_queue()) {
            fulfill(zip(resultA, resultB, resultC, resultD))
        }
    }
}

public func zipArray<T>(promises: [Promise<T>]) -> Promise<[T]> {
    return Promise { fulfill in
        let group = dispatch_group_create()

        var results: [Result<T>?] = Array(count: promises.count, repeatedValue: nil)

        for (index, promise) in promises.enumerate() {
            dispatch_group_enter(group)
            promise.call { result in
                results[index] = result
                dispatch_group_leave(group)
            }
        }
        
        dispatch_group_notify(group, dispatch_get_main_queue()) {
            let unwrappedResults = results.map { $0! }
            fulfill(zipArray(unwrappedResults))
        }
    }
}
