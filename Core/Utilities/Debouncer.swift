//
//  Debouncer.swift
//  MacMount
//
//  Utility for debouncing rapid updates to improve performance
//

import Foundation

/// A thread-safe debouncer that coalesces rapid calls into a single execution
actor Debouncer {
    private var debounceTask: Task<Void, Never>?
    private let delay: TimeInterval
    
    init(delay: TimeInterval) {
        self.delay = delay
    }
    
    /// Debounce the execution of a function
    /// - Parameter action: The async function to execute after the delay
    func debounce(_ action: @escaping () async -> Void) {
        // Cancel any existing task
        debounceTask?.cancel()
        
        // Create new task with delay
        debounceTask = Task { [delay] in
            // Wait for the specified delay
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            
            // Check if task was cancelled during sleep
            guard !Task.isCancelled else { return }
            
            // Execute the action
            await action()
        }
    }
    
    /// Cancel any pending debounced action
    func cancel() {
        debounceTask?.cancel()
        debounceTask = nil
    }
}

/// A synchronous debouncer for use with @Published properties
@MainActor
class PublishedDebouncer<Value> {
    private var debounceTimer: Timer?
    private let delay: TimeInterval
    private let action: (Value) -> Void
    
    init(delay: TimeInterval, action: @escaping (Value) -> Void) {
        self.delay = delay
        self.action = action
    }
    
    func send(_ value: Value) {
        // Cancel existing timer
        debounceTimer?.invalidate()
        
        // Create new timer
        debounceTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.action(value)
        }
    }
    
    func cancel() {
        debounceTimer?.invalidate()
        debounceTimer = nil
    }
}

/// Extension for creating debounced Publishers
import Combine

extension Publisher {
    /// Debounces the publisher's output
    /// - Parameters:
    ///   - delay: The time interval to wait before emitting
    ///   - scheduler: The scheduler to use for timing
    /// - Returns: A publisher that emits values after the delay
    func smartDebounce<S: Scheduler>(
        for delay: S.SchedulerTimeType.Stride,
        scheduler: S
    ) -> AnyPublisher<Output, Failure> {
        self
            .throttle(for: .zero, scheduler: scheduler, latest: true)
            .debounce(for: delay, scheduler: scheduler)
            .eraseToAnyPublisher()
    }
}