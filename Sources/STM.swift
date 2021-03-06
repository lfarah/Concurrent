//
//  STM.swift
//  Concurrent
//
//  Created by Robert Widmann on 9/27/15.
//  Copyright © 2015 TypeLift. All rights reserved.
//
// This file is a fairly clean port of FSharpX's implementation 
// ~(https://github.com/fsprojects/FSharpx.Extras/)

/// A monad supporting atomic memory transactions.
public struct STM<T> {
	/// Perform a series of STM actions atomically.
	public func atomically() -> T {
		do {
			return try TLog.atomically { try self.unSTM($0) }
		} catch _ {
			fatalError("Retry should have been caught internally.")
		}
	}

	/// Retry execution of the current memory transaction because it has seen 
	/// values in `TVar`s which mean that it should not continue. 
	///
	/// The implementation may block the thread until one of the `TVar`s that it
	/// has read from has been udpated.
	public static func retry() -> STM<T>  {
		return STM { trans in
			return try trans.retry()
		}
	}
	
	/// Compose two alternative STM actions (GHC only). 
	///
	/// If the first action completes without retrying then it forms the result
	/// of the `orElse`. Otherwise, if the first action retries, then the second
	/// action is tried in its place. If both actions retry then the `orElse` as
	/// a whole retries.
	public func orElse(b : STM<T>) -> STM<T>  {
		return STM { trans in
			do {
				return try trans.orElse(self.unSTM, q: b.unSTM)
			} catch _ {
				fatalError()
			}
		}
	}
	
	private let unSTM : TLog throws -> T
	
	internal init(_ unSTM : TLog throws -> T) {
		self.unSTM = unSTM
	}
}

extension STM /*: Functor*/ {
	/// Apply a function to the result of an STM transaction.
	public func fmap<B>(f : T -> B) -> STM<B> {
		return self.flatMap { x in STM<B>.pure(f(x)) }
	}
}

extension STM /*: Pointed*/ {
	/// Lift a value into a trivial STM transaction.
	public static func pure<T>(x : T) -> STM<T> {
		return STM<T> { _ in
			return x
		}
	}
}

extension STM /*: Applicative*/ {
	/// Atomically apply a function to the result of an STM transaction.
	public func ap<B>(fab : STM<T -> B>) -> STM<B> {
		return fab.flatMap(self.fmap)
	}
}

extension STM /*: Monad*/ {
	/// Atomically apply a function to the result of an STM transaction that
	/// yields a continuation transaction to be executed later.
	///
	/// This function can be used to implement other atomic primitives.
	public func flatMap<B>(rest : T -> STM<B>) -> STM<B> {
		return STM<B> { trans in
			return try rest(try! self.unSTM(trans)).unSTM(trans)
		}
	}

	/// Atomically execute the first action then execute the second action
	/// immediately after.
	public func then<B>(then : STM<B>) -> STM<B> {
		return self.flatMap { _ in
			return then
		}
	}
}
