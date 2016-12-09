//
//  RSpecReporter.swift
//  pxctest
//
//  Created by Johannes Plunien on 23/11/16.
//  Copyright © 2016 Johannes Plunien. All rights reserved.
//

import FBSimulatorControl
import Foundation

final class RSpecReporter: FBTestManagerTestReporterBase, ConsoleReporter {

    let consoleOutput: ConsoleOutput
    let simulatorIdentifier: String
    var summary: FBTestManagerResultSummary? {
        return testSuite.summary
    }
    let testTargetName: String

    init(simulatorIdentifier: String, testTargetName: String, consoleOutput: ConsoleOutput) {
        self.consoleOutput = consoleOutput
        self.simulatorIdentifier = simulatorIdentifier
        self.testTargetName = testTargetName
        super.init()
    }

    static func finishReporting(consoleOutput: ConsoleOutput, reporters: [ConsoleReporter]) throws {
        reporters.flatMap { $0 as? RSpecReporter }.forEach { $0.writeFailures() }
        reporters.flatMap { $0 as? RSpecReporter }.forEach { $0.writeSummary() }

        let runCount = reporters.reduce(0) { $0 + ($1.summary?.runCount ?? 0) }
        let failureCount = reporters.reduce(0) { $0 + ($1.summary?.failureCount ?? 0) }
        let unexpected = reporters.reduce(0) { $0 + ($1.summary?.unexpected ?? 0) }
        let output = String(format: "\(ANSI.bold)Total - Finished executing %d tests. %d Failures, %d Unexpected\(ANSI.reset)", runCount, failureCount, unexpected)

        consoleOutput.write(line: output)

        try raiseTestRunHadFailures(reporters: reporters)
    }

    // MARK: - FBTestManagerTestReporter

    override func testManagerMediator(_ mediator: FBTestManagerAPIMediator!, testCaseDidFinishForTestClass testClass: String!, method: String!, with status: FBTestReportStatus, duration: TimeInterval) {
        switch status {
        case .unknown:
            consoleOutput.write(output: "?")
        case .passed:
            consoleOutput.write(output: ".")
        case .failed:
            consoleOutput.write(output: "F")
        }

        super.testManagerMediator(mediator, testCaseDidFinishForTestClass: testClass, method: method, with: status, duration: duration)
    }

    // MARK: - Private

    private func writeFailures() {
        guard let summary = testSuite.summary else { return }

        if summary.failureCount > 0 {
            consoleOutput.write(line: "\(ANSI.bold)\(testTargetName)\(ANSI.reset)")
            consoleOutput.write(line: "  \(ANSI.bold)Failures on \(simulatorIdentifier):\(ANSI.reset)")
            writeFailures(testSuite: testSuite)
        }
    }

    private func writeFailures(testSuite: FBTestManagerTestReporterTestSuite) {
        for testCase in testSuite.testCases {
            guard testCase.failures.count > 0 else { continue }
            consoleOutput.write(line: "    -[\(testCase.testClass) \(testCase.method)]")
            for failure in testCase.failures {
                let filename = URL(fileURLWithPath: failure.file).lastPathComponent
                consoleOutput.write(line: "      \(filename):\(failure.line) \(failure.message)")
            }
        }
        for testSuite in testSuite.testSuites {
            writeFailures(testSuite: testSuite)
        }
    }

    private func writeSummary() {
        guard let summary = testSuite.summary else { return }

        let output = String(format: "\(testTargetName) - \(simulatorIdentifier) - Finished executing %d tests after %.03fs. %d Failures, %d Unexpected", summary.runCount, summary.totalDuration, summary.failureCount, summary.unexpected)
        consoleOutput.write(line: output)
    }

}
