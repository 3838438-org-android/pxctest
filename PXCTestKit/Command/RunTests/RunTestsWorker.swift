//
//  RunTestsWorker.swift
//  pxctest
//
//  Created by Johannes Plunien on 29/12/2016.
//  Copyright © 2016 Johannes Plunien. All rights reserved.
//

import FBSimulatorControl
import Foundation

final class RunTestsWorker {

    let name: String
    let applications: [FBApplicationDescriptor]
    let simulator: FBSimulator
    let targetName: String
    let testLaunchConfiguration: FBTestLaunchConfiguration

    var configuration: FBSimulatorConfiguration {
        return simulator.configuration!
    }

    private(set) var errors: [RunTestsError] = []

    init(name: String, applications: [FBApplicationDescriptor], simulator: FBSimulator, targetName: String, testLaunchConfiguration: FBTestLaunchConfiguration) {
        self.name = name
        self.applications = applications
        self.simulator = simulator
        self.targetName = targetName
        self.testLaunchConfiguration = testLaunchConfiguration
    }

    func abortTestRun() throws {
        for application in applications {
            try simulator.killApplication(withBundleID: application.bundleID)
        }
    }

    func cleanUpLogFiles(fileManager: RunTestsFileManager) throws {
        let logFilesPath = fileManager.urlFor(worker: self).path
        for logFilePath in FBFileFinder.contentsOfDirectory(withBasePath: logFilesPath) {
            let temporaryFilePath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString).path
            guard
                let reader = FileReader(path: logFilePath),
                let writer = FileWriter(path: temporaryFilePath)
            else { continue }
            for line in reader {
                writer.write(string: line.replacingOccurrences(of: "XCTestOutputBarrier", with: ""))
            }
            try FileManager.default.removeItem(atPath: logFilePath)
            try FileManager.default.moveItem(atPath: temporaryFilePath, toPath: logFilePath)
        }
    }

    func extractDiagnostics(fileManager: RunTestsFileManager) throws {
        for error in errors {
            for crash in error.crashes {
                let destinationPath = fileManager.urlFor(worker: self).path
                try crash.writeOut(toDirectory: destinationPath)
            }
        }
    }

    func startTests(context: RunTestsContext, reporters: RunTestsReporters) throws {
        let workingDirectoryURL = context.fileManager.urlFor(worker: self)
        let testsToRun = context.testsToRun[name] ?? Set<String>()
        let testEnvironment = Environment.injectPrefixedVariables(
            from: context.environment,
            into: testLaunchConfiguration.testEnvironment,
            workingDirectoryURL: workingDirectoryURL
        )

        let bundleName = self.testLaunchConfiguration.applicationLaunchConfiguration!.bundleName!
        let outputPath = workingDirectoryURL.appendingPathComponent("\(bundleName).log").path

        let applicationLaunchConfiguration = self.testLaunchConfiguration
            .applicationLaunchConfiguration!
            .withOutput(try FBProcessOutputConfiguration(stdOut: outputPath, stdErr: outputPath))

        let testLaunchConfigurartion = self.testLaunchConfiguration
            .withTestsToRun(testsToRun.union(self.testLaunchConfiguration.testsToRun ?? Set<String>()))
            .withTestEnvironment(testEnvironment)
            .withApplicationLaunchConfiguration(applicationLaunchConfiguration)

        let reporter = try reporters.addReporter(for: simulator, name: name, testTargetName: targetName)

        try simulator.startTest(with: testLaunchConfigurartion, reporter: reporter)
    }

    func waitForTestResult(timeout: TimeInterval) {
        let testManagerResults = simulator.resourceSink.testManagers.flatMap { $0.waitUntilTestingHasFinished(withTimeout: timeout) }
        if testManagerResults.reduce(true, { $0 && $1.didEndSuccessfully }) {
            return
        }
        errors.append(
            RunTestsError(
                simulator: simulator,
                target: name,
                errors: testManagerResults.flatMap { $0.error },
                crashes: testManagerResults.flatMap { $0.crashDiagnostic }
            )
        )
    }

}

extension Sequence where Iterator.Element == RunTestsWorker {

    func abortTestRun() throws {
        for worker in self {
            try worker.abortTestRun()
        }
    }

    func boot(context: BootContext) throws {
        for worker in self {
            guard worker.simulator.state != .booted else { continue }
            try worker.simulator.boot(context: context)
        }
    }

    func installApplications() throws {
        for worker in self {
            try worker.simulator.install(applications: worker.applications)
        }
    }

    func loadDefaults(context: DefaultsContext) throws {
        for worker in self {
            try worker.simulator.loadDefaults(context: context)
        }
    }

    func overrideWatchDogTimer() throws {
        for worker in self {
            let applications = worker.applications.map { $0.bundleID }
            try worker.simulator.overrideWatchDogTimer(forApplications: applications, withTimeout: 60.0)
        }
    }

    func startTests(context: RunTestsContext, reporters: RunTestsReporters) throws {
        for worker in self {
            try worker.startTests(context: context, reporters: reporters)
        }
    }

    func waitForTestResult(context: TestResultContext) throws -> [RunTestsError] {
        for worker in self {
            worker.waitForTestResult(timeout: context.timeout)
        }

        for worker in self {
            try worker.extractDiagnostics(fileManager: context.fileManager)
        }

        for worker in self {
            try worker.cleanUpLogFiles(fileManager: context.fileManager)
        }

        return flatMap { $0.errors }
    }

}
