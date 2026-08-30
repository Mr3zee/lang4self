import XCTest

@MainActor
final class Lang4SelfUITests: XCTestCase {
    private var app: XCUIApplication!
    private var testDirectory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false

        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Lang4SelfUITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)

        app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "-ApplePersistenceIgnoreState", "YES",
            "-AppleKeyboardUIMode", "3"
        ]
        app.launchEnvironment["LANG4SELF_UI_TEST_DATABASE"] = testDirectory
            .appendingPathComponent("fixture.sqlite3")
            .path
        app.launch()

        XCTAssertTrue(app.textFields["dictionary.search"].waitForExistence(timeout: 8))
        assertFocused(app.textFields["dictionary.search"])
    }

    override func tearDownWithError() throws {
        app?.terminate()
        if let testDirectory {
            try? FileManager.default.removeItem(at: testDirectory)
        }
    }

    func testGlobalNavigationFindSettingsAndShortcutReference() {
        for (key, route) in [
            ("1", "dictionary"),
            ("2", "speak"),
            ("3", "review"),
            ("4", "library"),
            ("5", "sentences"),
            ("6", "settings")
        ] {
            app.typeKey(key, modifierFlags: .command)
            XCTAssertTrue(routeElement(route).waitForExistence(timeout: 3), "⌘\(key) did not open \(route)")
        }

        for route in ["dictionary", "speak", "review", "library", "sentences", "settings"] {
            element("sidebar.\(route)").click()
            XCTAssertTrue(routeElement(route).waitForExistence(timeout: 3), "Sidebar did not open \(route)")
        }

        element("sidebar.get-full-dictionary").click()
        XCTAssertTrue(routeElement("settings").waitForExistence(timeout: 3))

        app.typeKey("1", modifierFlags: .command)
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(routeElement("settings").waitForExistence(timeout: 3))

        app.typeKey("?", modifierFlags: .command)
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 3))
        for heading in ["Global", "Dictionary", "Speak", "Review", "Lists and sentences", "Dialogs and controls", "Standard macOS"] {
            XCTAssertTrue(app.staticTexts[heading].exists, "Missing shortcut group: \(heading)")
        }
        app.typeKey(.space, modifierFlags: [])
        XCTAssertTrue(app.sheets.firstMatch.waitForNonExistence(timeout: 3))

        app.typeKey("?", modifierFlags: .command)
        XCTAssertTrue(app.buttons["shortcuts.close"].waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.sheets.firstMatch.waitForNonExistence(timeout: 3))

        app.typeKey("?", modifierFlags: .command)
        XCTAssertTrue(app.buttons["shortcuts.close"].waitForExistence(timeout: 3))
        app.buttons["shortcuts.close"].click()
        XCTAssertTrue(app.sheets.firstMatch.waitForNonExistence(timeout: 3))

        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(routeElement("dictionary").waitForExistence(timeout: 3))
        assertFocused(app.textFields["dictionary.search"])
        app.typeText("Haus")
        XCTAssertTrue(app.buttons["dictionary.clear-search"].waitForExistence(timeout: 3))

        openRoute("4", route: "library")
        app.typeKey("f", modifierFlags: .command)
        assertFocused(app.textFields["library.search"])
        app.typeText("Haus")
        XCTAssertEqual(app.textFields["library.search"].value as? String, "Haus")
    }

    func testDictionaryKeyboardSearchSelectionAddAndClear() {
        assertFocused(app.textFields["dictionary.search"])
        app.typeText("Haus")
        XCTAssertTrue(app.buttons["dictionary.clear-search"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["dictionary.add-selected"].waitForExistence(timeout: 3))

        app.typeKey(.return, modifierFlags: [])
        assertFocused(element("dictionary.results"))
        app.typeKey(.return, modifierFlags: .command)
        XCTAssertTrue(app.buttons["banner.dismiss"].waitForExistence(timeout: 3))
        app.buttons["banner.dismiss"].click()
        XCTAssertTrue(app.buttons["banner.dismiss"].waitForNonExistence(timeout: 3))

        app.typeKey("f", modifierFlags: .command)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.buttons["dictionary.clear-search"].waitForNonExistence(timeout: 3))
        assertFocused(app.textFields["dictionary.search"])

        app.typeText("lernen")
        XCTAssertTrue(app.staticTexts["lernen"].waitForExistence(timeout: 3))
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(app.buttons["dictionary.add-selected"].waitForExistence(timeout: 3))

        app.typeKey("f", modifierFlags: .command)
        app.buttons["dictionary.clear-search"].click()
        XCTAssertTrue(app.buttons["dictionary.clear-search"].waitForNonExistence(timeout: 3))
    }

    func testSpeakRecordingControlAndConfirmationAreKeyboardOperable() {
        openRoute("2", route: "speak")
        let recordButton = app.buttons["speak.record"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 3))

        waitForUIToSettle()
        app.typeKey(.space, modifierFlags: [])
        XCTAssertTrue(app.buttons["speak.confirm"].waitForExistence(timeout: 3))
        let results = element("speak.results")
        XCTAssertTrue(results.waitForExistence(timeout: 3))
        assertFocused(results)
        XCTAssertTrue(app.staticTexts["Part of speech: Noun"].firstMatch.exists)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.buttons["banner.dismiss"].waitForExistence(timeout: 3))

        waitForUIToSettle()
        let idleFrame = recordButton.frame

        recordButton.click()
        XCTAssertEqual(recordButton.label, "Stop recording")
        waitForUIToSettle()
        XCTAssertEqual(recordButton.frame.width, idleFrame.width, accuracy: 1)
        XCTAssertEqual(recordButton.frame.midX, idleFrame.midX, accuracy: 1)

        recordButton.click()
        XCTAssertTrue(app.buttons["speak.confirm"].waitForExistence(timeout: 3))
    }

    func testSpaceOpensSpeakAndRecordsFromAnotherPage() {
        openRoute("6", route: "settings")

        app.typeKey(.space, modifierFlags: [])

        XCTAssertTrue(app.buttons["speak.record"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["speak.confirm"].waitForExistence(timeout: 3))
        let results = element("speak.results")
        XCTAssertTrue(results.waitForExistence(timeout: 3))
        assertFocused(results)
    }

    func testReviewRevealAndEveryRatingShortcut() {
        for rating in ["1", "2", "3", "4"] {
            relaunchFixture()
            openRoute("3", route: "review")
            XCTAssertTrue(app.buttons["review.reveal"].waitForExistence(timeout: 3))

            app.typeKey(.space, modifierFlags: [])
            XCTAssertTrue(app.buttons["review.rating.\(rating)"].waitForExistence(timeout: 3))
            app.typeKey(rating, modifierFlags: [])
            XCTAssertTrue(app.buttons["review.reveal"].waitForExistence(timeout: 3))
        }
    }

    func testReviewPromptShowsPartOfSpeechBeforeReveal() {
        openRoute("3", route: "review")

        let partOfSpeech = element("review.part-of-speech")
        XCTAssertTrue(partOfSpeech.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Part of speech: Noun"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["review.reveal"].exists)
    }

    func testReviewListScopeCompletionAndRestart() {
        openRoute("3", route: "review")

        element("review.list-picker").click()
        app.menuItems["Travel"].click()
        XCTAssertTrue(app.buttons["review.reveal"].waitForExistence(timeout: 3))

        let scope = element("review.scope")
        XCTAssertEqual(scope.label, "Review All")
        scope.click()
        XCTAssertTrue(waitUntil { scope.label == "Due Only" })

        app.typeKey(.space, modifierFlags: [])
        app.typeKey("4", modifierFlags: [])
        XCTAssertTrue(app.buttons["review.restart"].waitForExistence(timeout: 3))

        app.typeKey(.space, modifierFlags: [])
        XCTAssertTrue(app.buttons["review.reveal"].waitForExistence(timeout: 3))
        scope.click()
        XCTAssertTrue(waitUntil { scope.label == "Review All" })
    }

    func testListCreationRenameDeletionSearchAndEditorFocus() {
        openLibrary()

        app.typeKey("f", modifierFlags: .command)
        app.typeText("Haus")
        XCTAssertEqual(app.textFields["library.search"].value as? String, "Haus")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertEqual(app.textFields["library.search"].value as? String, "")

        openRoute("1", route: "dictionary")
        openLibrary()

        element("library.new-list").click()
        XCTAssertTrue(app.textFields["list-editor.name"].waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.textFields["list-editor.name"].waitForNonExistence(timeout: 3))
        waitForUIToSettle()

        app.typeKey(.return, modifierFlags: [])
        let germanField = app.textFields["card-editor.german"]
        XCTAssertTrue(germanField.waitForExistence(timeout: 3))
        assertFocused(germanField)
        app.typeKey("a", modifierFlags: .command)
        app.typeText("Edited Haus")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(germanField.waitForNonExistence(timeout: 3))

        app.typeKey("n", modifierFlags: [.command, .shift])
        let nameField = app.textFields["list-editor.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        assertFocused(nameField)
        app.typeText("Keyboard List")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["No saved entries"].waitForExistence(timeout: 3))

        element("library.list-actions").click()
        app.menuItems["Rename List…"].click()
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        app.typeKey("a", modifierFlags: .command)
        app.typeText("Renamed List")
        app.typeKey(.return, modifierFlags: [])

        element("library.list-actions").click()
        app.menuItems["Delete List…"].click()
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.sheets.firstMatch.waitForNonExistence(timeout: 3))

        element("library.list-actions").click()
        app.menuItems["Delete List…"].click()
        app.sheets.firstMatch.buttons["Delete List"].click()
        XCTAssertTrue(app.staticTexts["Haus"].waitForExistence(timeout: 3))
    }

    func testCardEditorSaveFieldsPickersAndListMembershipActions() {
        openLibrary()

        app.typeKey(.return, modifierFlags: [])
        let german = app.textFields["card-editor.german"]
        XCTAssertTrue(german.waitForExistence(timeout: 3))
        assertFocused(german)
        app.typeKey("a", modifierFlags: .command)
        app.typeText("Saved Haus")

        app.typeKey(.tab, modifierFlags: [])
        let translations = app.textFields["card-editor.translations"]
        assertFocused(translations)
        app.typeKey(.tab, modifierFlags: .shift)
        assertFocused(german)
        app.typeKey(.tab, modifierFlags: [])
        app.typeKey("a", modifierFlags: .command)
        app.typeText("saved house")

        app.textFields["card-editor.tags"].click()
        app.typeText("ui-test")
        app.textFields["card-editor.notes"].click()
        app.typeText("Edited entirely from the keyboard")
        element("card-editor.kind").click()
        app.menuItems["Phrase"].click()
        element("card-editor.gender").click()
        app.menuItems["das"].click()

        app.buttons["card-editor.save"].click()
        XCTAssertTrue(german.waitForNonExistence(timeout: 3))
        let savedHaus = app.staticTexts.matching(
            NSPredicate(format: "value CONTAINS %@", "Saved Haus")
        ).firstMatch
        XCTAssertTrue(savedHaus.waitForExistence(timeout: 3))
        assertFocused(element("library.cards"))
        waitForUIToSettle()

        element("library.cards").click()
        app.typeKey(.upArrow, modifierFlags: [])
        XCTAssertTrue(
            waitUntil { self.app.buttons["library.edit-card"].label == "Edit lernen" },
            "Up Arrow did not select the previous card"
        )
        element("library.more-actions").click()
        app.menuItems["Add to List"].click()
        app.menuItems["Travel"].click()
        XCTAssertTrue(app.buttons["banner.dismiss"].waitForExistence(timeout: 3))
        app.buttons["banner.dismiss"].click()

        element("library.list-picker").click()
        app.menuItems["Travel"].click()
        XCTAssertTrue(app.staticTexts["lernen"].waitForExistence(timeout: 3))
        element("library.cards").staticTexts["lernen"].click()
        element("library.more-actions").click()
        app.menuItems["Remove from List"].click()
        XCTAssertTrue(app.staticTexts["lernen"].waitForNonExistence(timeout: 3))

        element("library.list-picker").click()
        element("library.list-picker").menuItems["My words"].click()
        XCTAssertTrue(app.staticTexts["lernen"].waitForExistence(timeout: 3))
    }

    func testAllVisibleCardActionsAndKeyboardDelete() {
        openLibrary()

        let star = app.buttons["library.star-card"]
        XCTAssertTrue(star.waitForExistence(timeout: 3))
        star.click()
        XCTAssertTrue(app.buttons["Unstar"].waitForExistence(timeout: 3))
        app.buttons["Unstar"].click()
        XCTAssertTrue(app.buttons["Star"].waitForExistence(timeout: 3))

        element("library.more-actions").click()
        app.menuItems["Suspend Reviews"].click()
        XCTAssertTrue(app.staticTexts["Suspended"].waitForExistence(timeout: 3))

        element("library.more-actions").click()
        app.menuItems["Resume Reviews"].click()
        XCTAssertTrue(app.staticTexts["Suspended"].waitForNonExistence(timeout: 3))

        element("library.more-actions").click()
        XCTAssertTrue(app.menuItems["Add to List"].exists)
        app.typeKey(.escape, modifierFlags: [])

        app.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Haus"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["lernen"].exists)
    }

    func testSentenceSelectionCheckboxesSavingDeletionAndTokenFocus() {
        openRoute("5", route: "sentences")
        XCTAssertTrue(element("sentences.list").waitForExistence(timeout: 3))
        assertFocused(element("sentences.list"))
        XCTAssertGreaterThanOrEqual(app.checkBoxes.count, 2)

        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.buttons["sentence.token.0"].waitForExistence(timeout: 3))
        assertFocused(app.buttons["sentence.token.0"])
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Kind"].waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])
        assertFocused(element("sentences.list"))

        app.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Das Kind liest ein Buch."].waitForNonExistence(timeout: 3))

        let firstCheckbox = app.checkBoxes.firstMatch
        let oldValue = String(describing: firstCheckbox.value)
        firstCheckbox.click()
        XCTAssertNotEqual(String(describing: firstCheckbox.value), oldValue)

        let selectAll = app.buttons["sentences.select-all"]
        let saveSelected = app.buttons["sentences.save-selected"]
        selectAll.click()
        if saveSelected.isEnabled { selectAll.click() }
        XCTAssertFalse(saveSelected.isEnabled)
        selectAll.click()
        XCTAssertTrue(saveSelected.isEnabled)
        saveSelected.click()
        XCTAssertTrue(app.buttons["banner.dismiss"].waitForExistence(timeout: 3))
    }

    func testSentenceGenerationListCountAndGenerateControls() {
        openRoute("5", route: "sentences")

        element("sentences.list-picker").click()
        app.menuItems["Travel"].click()

        let count = element("sentences.count")
        XCTAssertTrue(count.exists)
        count.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).click()

        element("sentences.generate").click()
        XCTAssertTrue(app.staticTexts["Das Haus hat ein rotes Dach."].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Der Zug kommt pünktlich an."].waitForExistence(timeout: 3), "Stepper did not increase generation count")
        XCTAssertEqual(app.checkBoxes.count, 6)
    }

    func testSettingsControlsImportersAndEmbeddedShortcutList() {
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(routeElement("settings").waitForExistence(timeout: 3))

        XCTAssertTrue(app.links["Request DE → EN file"].exists)
        XCTAssertTrue(app.links["Request DE → RU file"].exists)
        XCTAssertTrue(app.links["Source and license"].exists)
        XCTAssertTrue(app.popUpButtons["Model"].exists)
        XCTAssertTrue(app.popUpButtons["Context window"].exists)
        XCTAssertTrue(app.popUpButtons["Maximum output tokens"].exists)
        XCTAssertGreaterThanOrEqual(app.sliders.count, 2)
        XCTAssertTrue(app.buttons["settings.reset-model-defaults"].exists)

        for shortcut in ["⌘1 … ⌘6", "⌘,", "⌘F", "⌘?", "⌘Return", "⌘⇧N", "1 … 4", "Delete", "⌘Q", "⌘Z / ⇧⌘Z"] {
            XCTAssertTrue(app.staticTexts[shortcut].exists, "Settings is missing \(shortcut)")
        }

        app.buttons["settings.import-dictionary"].click()
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.buttons["settings.import-dictionary"].waitForExistence(timeout: 3))

        app.buttons["settings.import-explanations"].click()
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.buttons["settings.import-explanations"].waitForExistence(timeout: 3))

        app.scrollViews.firstMatch.swipeUp()
        let model = element("settings.model")
        model.click()
        app.menuItems["UI Test Model — 1B · 1 GB"].click()

        element("settings.context-window").click()
        app.menuItems["32,768 tokens"].click()
        element("settings.max-output").click()
        app.menuItems["8,192 tokens"].click()

        let temperature = element("settings.temperature")
        let topP = element("settings.top-p")
        temperature.adjust(toNormalizedSliderPosition: 0.8)
        topP.adjust(toNormalizedSliderPosition: 0.2)
        element("settings.gpu-offload").radioButtons["CPU only"].click()

        app.buttons["settings.reset-model-defaults"].click()
        XCTAssertTrue(app.buttons["settings.refresh-models"].exists)
        app.buttons["settings.refresh-models"].click()
    }

    func testAccessibilityAuditOnEveryScreen() throws {
        for (key, route) in [("1", "dictionary"), ("2", "speak"), ("3", "review"), ("4", "library"), ("5", "sentences"), ("6", "settings")] {
            openRoute(key, route: route)
            // Other macOS audit types currently flag system menus and standard SwiftUI layout controls.
            try app.performAccessibilityAudit(for: .elementDetection)
        }
    }

    private func openLibrary() {
        openRoute("4", route: "library")
        XCTAssertTrue(element("library.cards").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Haus"].waitForExistence(timeout: 3))
    }

    private func openRoute(_ shortcut: String, route: String) {
        app.typeKey(shortcut, modifierFlags: .command)
        XCTAssertTrue(routeElement(route).waitForExistence(timeout: 3))
    }

    private func routeElement(_ route: String) -> XCUIElement {
        switch route {
        case "dictionary": return app.textFields["dictionary.search"]
        case "speak": return app.buttons["speak.record"]
        case "review": return app.buttons["review.reveal"]
        case "library": return element("library.cards")
        case "sentences": return element("sentences.list")
        case "settings": return app.buttons["settings.import-dictionary"]
        default: XCTFail("Unknown route \(route)"); return app.windows.firstMatch
        }
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func assertFocused(
        _ element: XCUIElement,
        timeout: TimeInterval = 3,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            waitUntil(timeout: timeout) {
                (element.value(forKey: "hasKeyboardFocus") as? Bool) == true
            },
            "Expected \(element) to have keyboard focus",
            file: file,
            line: line
        )
    }

    private func waitForUIToSettle(_ delay: TimeInterval = 0.25) {
        let readyAt = Date().addingTimeInterval(delay)
        _ = waitUntil(timeout: delay + 0.5) { Date() >= readyAt }
    }

    @discardableResult
    private func waitUntil(timeout: TimeInterval = 3, condition: @escaping () -> Bool) -> Bool {
        let predicate = NSPredicate { _, _ in condition() }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        return result == .completed
    }

    private func relaunchFixture() {
        app.terminate()
        try? FileManager.default.removeItem(at: testDirectory)
        try? FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
        app.launch()
        XCTAssertTrue(app.textFields["dictionary.search"].waitForExistence(timeout: 8))
    }
}
