import XCTest
@testable import CashbackCounter

@MainActor
final class AddTransactionSaveControllerTests: XCTestCase {
    private enum StubSaveError: LocalizedError {
        case failed

        var errorDescription: String? {
            "模拟保存失败"
        }
    }

    func testSaveFailureDoesNotDismissShowsErrorAndDoesNotNotifyOnSaved() async {
        let controller = AddTransactionSaveController()
        var didDismiss = false
        var didCallOnSaved = false

        await controller.save(
            operation: {
                throw StubSaveError.failed
            },
            dismiss: {
                didDismiss = true
            },
            onSaved: {
                didCallOnSaved = true
            }
        )

        XCTAssertFalse(didDismiss)
        XCTAssertFalse(didCallOnSaved)
        XCTAssertFalse(controller.isSaving)
        XCTAssertTrue(controller.isShowingErrorAlert)
        XCTAssertEqual(controller.errorMessage, "模拟保存失败")
    }

    func testConcurrentSaveTapIsIgnoredWhileSaveIsInProgress() async {
        let controller = AddTransactionSaveController()
        var saveAttempts = 0
        var dismissCount = 0
        var onSavedCount = 0
        var continuation: CheckedContinuation<Void, Never>?

        let firstSave = Task { @MainActor in
            await controller.save(
                operation: {
                    saveAttempts += 1
                    await withCheckedContinuation { pendingSave in
                        continuation = pendingSave
                    }
                },
                dismiss: {
                    dismissCount += 1
                },
                onSaved: {
                    onSavedCount += 1
                }
            )
        }

        for _ in 0..<100 where !controller.isSaving {
            await Task.yield()
        }
        XCTAssertTrue(controller.isSaving)

        await controller.save(
            operation: {
                saveAttempts += 1
            },
            dismiss: {
                dismissCount += 1
            },
            onSaved: {
                onSavedCount += 1
            }
        )

        XCTAssertEqual(saveAttempts, 1)
        XCTAssertTrue(controller.isSaving)

        guard let continuation else {
            XCTFail("Expected first save operation to be suspended")
            firstSave.cancel()
            return
        }

        continuation.resume()
        await firstSave.value

        XCTAssertFalse(controller.isSaving)
        XCTAssertEqual(dismissCount, 1)
        XCTAssertEqual(onSavedCount, 1)
        XCTAssertNil(controller.errorMessage)
    }
}
