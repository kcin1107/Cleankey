import Testing
@testable import Cleankey

@MainActor
struct UpdateCheckerTests {
    @Test
    func newerReleaseIsAvailable() async {
        let checker = makeChecker(latestVersion: "1.10", currentVersion: "1.9")

        await checker.check()

        #expect(checker.state == .available("1.10"))
    }

    @Test(arguments: ["1.10", "1.9"])
    func currentOrOlderReleaseIsUpToDate(latestVersion: String) async {
        let checker = makeChecker(latestVersion: latestVersion, currentVersion: "1.10")

        await checker.check()

        #expect(checker.state == .upToDate)
    }

    @Test
    func failedRequestSetsFailureState() async {
        let dependencies = UpdateCheckerDependencies(
            currentVersion: "1.0",
            fetchLatestVersion: { throw TestError.requestFailed },
            openReleasesPage: {}
        )
        let checker = UpdateChecker(dependencies: dependencies)

        await checker.check()

        #expect(checker.state == .failed)
    }

    @Test
    func resetReturnsCompletedCheckToIdle() async {
        let checker = makeChecker(latestVersion: "1.0", currentVersion: "1.0")
        await checker.check()

        checker.reset()

        #expect(checker.state == .idle)
    }

    @Test
    func actionOpensReleasesPageWhenUpdateIsAvailable() async {
        var didOpenReleasesPage = false
        let dependencies = UpdateCheckerDependencies(
            currentVersion: "1.0",
            fetchLatestVersion: { "2.0" },
            openReleasesPage: { didOpenReleasesPage = true }
        )
        let checker = UpdateChecker(dependencies: dependencies)
        await checker.check()

        checker.act()

        #expect(didOpenReleasesPage)
    }

    private func makeChecker(latestVersion: String, currentVersion: String) -> UpdateChecker {
        UpdateChecker(
            dependencies: UpdateCheckerDependencies(
                currentVersion: currentVersion,
                fetchLatestVersion: { latestVersion },
                openReleasesPage: {}
            )
        )
    }
}

private enum TestError: Error {
    case requestFailed
}
