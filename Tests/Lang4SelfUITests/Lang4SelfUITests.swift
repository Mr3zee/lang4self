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
        try writeDictionaryFixtures()

        app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "-ApplePersistenceIgnoreState", "YES",
            "-AppleKeyboardUIMode", "3"
        ]
        app.launchEnvironment["LANG4SELF_UI_TEST_DATABASE"] = testDirectory
            .appendingPathComponent("fixture.sqlite3")
            .path
        app.launchEnvironment["LANG4SELF_UI_TEST_ENGLISH_DICTIONARY"] = englishDictionaryURL.path
        app.launchEnvironment["LANG4SELF_UI_TEST_RUSSIAN_DICTIONARY"] = russianDictionaryURL.path
        app.launch()

        XCTAssertTrue(element("app.ready").waitForExistence(timeout: 12))
        XCTAssertTrue(app.textFields["dictionary.search"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["dictionary.voice-search"].waitForExistence(timeout: 3))
        assertFocused(app.buttons["dictionary.voice-search"])
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
            ("2", "review"),
            ("3", "library"),
            ("4", "sentences"),
            ("5", "settings")
        ] {
            app.typeKey(key, modifierFlags: .command)
            XCTAssertTrue(routeElement(route).waitForExistence(timeout: 3), "⌘\(key) did not open \(route)")
        }

        for route in ["dictionary", "review", "library", "sentences", "settings"] {
            element("sidebar.\(route)").click()
            XCTAssertTrue(routeElement(route).waitForExistence(timeout: 3), "Sidebar did not open \(route)")
        }

        element("sidebar.get-full-dictionary").click()
        XCTAssertTrue(routeElement("settings").waitForExistence(timeout: 3))

        app.typeKey("1", modifierFlags: .command)
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(routeElement("settings").waitForExistence(timeout: 3))

        app.typeKey("/", modifierFlags: .command)
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 3))
        for heading in ["Global", "Dictionary", "Review", "Lists and sentences", "Dialogs and controls", "Standard macOS"] {
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

        openRoute("3", route: "library")
        app.typeKey("f", modifierFlags: .command)
        assertFocused(app.textFields["library.search"])
        app.typeText("Haus")
        XCTAssertEqual(app.textFields["library.search"].value as? String, "Haus")
    }

    func testSidebarArrowNavigationWrapsWithoutLosingFocus() {
        app.typeKey("1", modifierFlags: .command)
        element("sidebar.dictionary").click()

        app.typeKey(.upArrow, modifierFlags: [])
        XCTAssertTrue(routeElement("settings").waitForExistence(timeout: 3))
        app.typeKey(.upArrow, modifierFlags: [])
        XCTAssertTrue(routeElement("sentences").waitForExistence(timeout: 3))

        element("sidebar.settings").click()
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(routeElement("dictionary").waitForExistence(timeout: 3))
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(routeElement("review").waitForExistence(timeout: 3))
    }

    func testSidebarEnterFocusesPagePrimaryContent() {
        let sidebar = element("sidebar.routes")

        element("sidebar.dictionary").click()
        assertFocused(sidebar)
        app.typeKey(.return, modifierFlags: [])
        assertFocused(app.textFields["dictionary.search"])

        app.typeText("Haus")
        XCTAssertTrue(element("dictionary.results").waitForExistence(timeout: 3))
        element("sidebar.dictionary").click()
        app.typeKey(.return, modifierFlags: [])
        assertFocused(element("dictionary.results"))

        element("sidebar.library").click()
        XCTAssertTrue(element("library.cards").waitForExistence(timeout: 3))
        app.typeKey(.return, modifierFlags: [])
        assertFocused(element("library.cards"))
        XCTAssertTrue(waitUntil { self.app.buttons["library.edit-card"].label == "Edit notes for Haus" })

        app.staticTexts["lernen"].click()
        XCTAssertTrue(waitUntil { self.app.buttons["library.edit-card"].label == "Edit notes for lernen" })
        element("sidebar.library").click()
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitUntil { self.app.buttons["library.edit-card"].label == "Edit notes for Haus" })

        element("library.new-list").click()
        let listName = app.textFields["list-editor.name"]
        XCTAssertTrue(listName.waitForExistence(timeout: 3))
        listName.typeText("Empty List")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["No saved entries"].waitForExistence(timeout: 3))
        element("sidebar.library").click()
        app.typeKey(.return, modifierFlags: [])
        assertFocused(app.textFields["library.search"])

        element("sidebar.sentences").click()
        XCTAssertTrue(element("sentences.list").waitForExistence(timeout: 3))
        app.typeKey(.return, modifierFlags: [])
        assertFocused(element("sentences.list"))
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(
                    format: "identifier BEGINSWITH %@",
                    "sentences.inspector.generated."
                ))
                .firstMatch
                .waitForExistence(timeout: 3)
        )

        let generatedRows = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "sentences.generated.")
        )
        let savedRows = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "sentences.saved.")
        )
        XCTAssertGreaterThan(generatedRows.count, 0)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitUntil { generatedRows.count == 0 && savedRows.count > 0 })

        element("sidebar.sentences").click()
        app.typeKey(.return, modifierFlags: [])
        assertFocused(element("sentences.list"))
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(
                    format: "identifier BEGINSWITH %@",
                    "sentences.inspector.saved."
                ))
                .firstMatch
                .waitForExistence(timeout: 3)
        )

        let visibleSavedRowIDs = {
            Set(savedRows.allElementsBoundByIndex.map(\.identifier))
        }
        while !visibleSavedRowIDs().isEmpty {
            let previousRows = visibleSavedRowIDs()
            app.typeKey(.delete, modifierFlags: [])
            XCTAssertTrue(waitUntil { visibleSavedRowIDs() != previousRows })
        }
        element("sidebar.sentences").click()
        app.typeKey(.return, modifierFlags: [])
        assertFocused(app.textFields["sentences.style"])

        for route in ["review", "settings"] {
            element("sidebar.\(route)").click()
            assertFocused(sidebar)
            app.typeKey(.return, modifierFlags: [])
            assertFocused(sidebar)
        }
    }

    func testCommandNOnlyCreatesAListInMyWords() {
        let initialWindowCount = app.windows.count

        app.menuBars.menuBarItems["File"].click()
        XCTAssertFalse(app.menuItems["New Window"].exists)
        XCTAssertFalse(app.menuItems["New List"].isEnabled)
        app.typeKey(.escape, modifierFlags: [])

        app.typeKey("n", modifierFlags: .command)
        XCTAssertEqual(app.windows.count, initialWindowCount)
        XCTAssertFalse(app.textFields["list-editor.name"].exists)

        openLibrary()
        app.menuBars.menuBarItems["File"].click()
        XCTAssertTrue(app.menuItems["New List"].isEnabled)
        app.typeKey(.escape, modifierFlags: [])

        app.typeKey("n", modifierFlags: [.command, .shift])
        XCTAssertFalse(app.textFields["list-editor.name"].exists)

        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.textFields["list-editor.name"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.windows.count, initialWindowCount)
    }

    func testDictionaryKeyboardSearchSelectionAddAndClear() {
        assertFocused(app.buttons["dictionary.voice-search"])
        app.typeKey("f", modifierFlags: .command)
        assertFocused(app.textFields["dictionary.search"])
        app.typeText("Haus")
        XCTAssertTrue(app.buttons["dictionary.clear-search"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["dictionary.add-selected"].waitForExistence(timeout: 3))

        app.typeKey(.return, modifierFlags: [])
        assertFocused(element("dictionary.results"))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.buttons["banner.dismiss"].waitForExistence(timeout: 3))
        app.buttons["banner.dismiss"].click()
        XCTAssertTrue(app.buttons["banner.dismiss"].waitForNonExistence(timeout: 3))

        app.typeKey("f", modifierFlags: .command)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.buttons["dictionary.clear-search"].waitForNonExistence(timeout: 3))
        assertFocused(app.buttons["dictionary.voice-search"])

        app.typeKey("f", modifierFlags: .command)
        assertFocused(app.textFields["dictionary.search"])

        app.typeText("lernen")
        XCTAssertTrue(app.staticTexts["lernen"].waitForExistence(timeout: 3))
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(app.buttons["dictionary.add-selected"].waitForExistence(timeout: 3))

        app.typeKey("f", modifierFlags: .command)
        app.buttons["dictionary.clear-search"].click()
        XCTAssertTrue(app.buttons["dictionary.clear-search"].waitForNonExistence(timeout: 3))
    }

    func testUndoRedoShortcutsForAddedAndRemovedContent() {
        app.typeKey("f", modifierFlags: .command)
        app.typeText("Mädchen")
        let addButton = app.buttons["dictionary.add-selected"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 3))
        addButton.click()
        XCTAssertTrue(app.buttons["banner.dismiss"].waitForExistence(timeout: 3))

        openLibrary()
        XCTAssertTrue(app.staticTexts["Mädchen"].waitForExistence(timeout: 3))

        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Mädchen"].waitForNonExistence(timeout: 3))

        app.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.staticTexts["Mädchen"].waitForExistence(timeout: 3))

        element("library.cards").staticTexts["Mädchen"].click()
        app.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Mädchen"].waitForNonExistence(timeout: 3))

        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Mädchen"].waitForExistence(timeout: 3))

        openRoute("4", route: "sentences")
        app.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Das Kind liest ein Buch."].waitForNonExistence(timeout: 3))

        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Das Kind liest ein Buch."].waitForExistence(timeout: 3))
        app.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.staticTexts["Das Kind liest ein Buch."].waitForNonExistence(timeout: 3))
    }

    func testDictionarySupportsEnglishTextAndGermanVoiceSearch() {
        let search = app.textFields["dictionary.search"]
        app.typeKey("f", modifierFlags: .command)
        assertFocused(search)
        search.typeText("to learn")
        XCTAssertEqual(search.value as? String, "to learn")
        XCTAssertTrue(app.staticTexts["lernen"].waitForExistence(timeout: 3))

        app.typeKey(.space, modifierFlags: [])
        XCTAssertEqual(search.value as? String, "to learn ")

        app.typeKey(.escape, modifierFlags: [])
        let voiceButton = app.buttons["dictionary.voice-search"]
        XCTAssertTrue(voiceButton.waitForExistence(timeout: 3))
        assertFocused(voiceButton)
        voiceButton.click()

        XCTAssertEqual(voiceButton.label, "Stop recording")
        XCTAssertTrue(element("dictionary.voice-status").waitForExistence(timeout: 3))
        voiceButton.click()

        XCTAssertEqual(search.value as? String, "Der Hund")
        let results = element("dictionary.results")
        XCTAssertTrue(results.waitForExistence(timeout: 3))
        assertFocused(results)
        XCTAssertTrue(app.staticTexts["Hund"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Hunde"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["dictionary.add-selected"].waitForExistence(timeout: 3))
    }

    func testVoiceSearchCyclesRecognitionAlternativesAndShowsConfidence() {
        let initialTextSearchCenterY = app.textFields["dictionary.search"].frame.midY
        let voiceButton = app.buttons["dictionary.voice-search"]
        voiceButton.click()
        voiceButton.click()

        let transcription = element("dictionary.voice-transcription")
        let confidence = element("dictionary.voice-confidence")
        XCTAssertTrue(transcription.waitForExistence(timeout: 3))
        XCTAssertEqual(elementText(transcription), "Der Hund")
        XCTAssertEqual(elementText(confidence), "1 of 3 · 96% confidence")
        XCTAssertEqual(
            app.textFields["dictionary.search"].frame.midY,
            initialTextSearchCenterY,
            accuracy: 0.5,
            "Showing a recognition result changed the speech panel height"
        )

        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(waitUntil {
            self.elementText(transcription) == "Die Hunde"
                && self.elementText(confidence) == "2 of 3 · 78% confidence"
        })
        app.typeKey(.leftArrow, modifierFlags: [])
        XCTAssertTrue(waitUntil { self.elementText(transcription) == "Der Hund" })
    }

    func testEntryDetailFoldsAdditionalEnglishAndRussianTranslations() {
        app.typeKey("f", modifierFlags: .command)
        app.typeText("Mädchen")

        let detail = element("entry.detail")
        XCTAssertTrue(detail.waitForExistence(timeout: 3))
        for translation in ["chick", "chit", "colleen"] {
            XCTAssertTrue(detail.staticTexts[translation].exists)
        }
        XCTAssertFalse(detail.staticTexts["gal"].exists)
        XCTAssertFalse(detail.staticTexts["девочка"].exists)

        let englishToggle = detail.buttons["entry.meanings.english.toggle"]
        XCTAssertTrue(englishToggle.exists)
        englishToggle.click()
        XCTAssertTrue(detail.staticTexts["gal"].waitForExistence(timeout: 3))

        let russianToggle = detail.buttons["entry.meanings.russian.toggle"]
        XCTAssertTrue(russianToggle.exists)
        russianToggle.click()
        XCTAssertTrue(detail.staticTexts["девочка"].waitForExistence(timeout: 3))
    }

    func testEntryDetailDoesNotRepeatGenericWordAndTranslationRows() {
        app.typeKey("f", modifierFlags: .command)
        app.typeText("ich")

        let detail = element("entry.detail")
        XCTAssertTrue(detail.waitForExistence(timeout: 3))
        XCTAssertTrue(detail.staticTexts["ich"].exists)
        XCTAssertTrue(detail.staticTexts["I"].exists)
        XCTAssertTrue(detail.staticTexts["me"].exists)
        XCTAssertFalse(detail.staticTexts["I; me"].exists)
        XCTAssertFalse(detail.staticTexts["German"].exists)
        XCTAssertFalse(detail.staticTexts["Translations"].exists)
    }

    func testGeneratedVerbAndAdjectiveFormsUseInformationalNotes() {
        app.typeKey("f", modifierFlags: .command)
        app.typeText("lernen")

        let note = element("entry.generated-forms")
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.staticTexts["Conjugation generated using regular verb rules."].waitForExistence(timeout: 3)
        )

        app.typeKey("f", modifierFlags: .command)
        app.typeKey("a", modifierFlags: .command)
        app.typeText("klein")

        XCTAssertTrue(
            app.staticTexts["Comparative and superlative generated using regular adjective rules."]
                .waitForExistence(timeout: 3)
        )
        XCTAssertFalse(
            app.staticTexts["Regular forms are estimated locally. Check irregular forms before memorising."].exists
        )
    }

    func testConsecutiveSpaceVoiceSearchesStayKeyboardOperable() {
        let leakedSpace = expectation(description: "No Space event reaches the focused results control")
        leakedSpace.isInverted = true
        leakedSpace.assertForOverFulfill = false
        let observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("Lang4SelfUITestingSpaceEventLeaked"),
            object: nil,
            queue: .main
        ) { _ in
            leakedSpace.fulfill()
        }
        defer { DistributedNotificationCenter.default().removeObserver(observer) }

        let recordButton = app.buttons["dictionary.voice-search"]
        assertFocused(recordButton)

        app.typeKey(.space, modifierFlags: [])
        let results = element("dictionary.results")
        XCTAssertTrue(results.waitForExistence(timeout: 3))
        assertFocused(results)

        simulateHeldSpaceWithRepeats()
        XCTAssertTrue(results.waitForExistence(timeout: 3))
        assertFocused(results)
        XCTAssertEqual(app.textFields["dictionary.search"].value as? String, "Der Hund")
        wait(for: [leakedSpace], timeout: 0.5)
    }

    func testDictionaryViewHandlesConsecutiveSpaceHoldsWithoutGlobalMonitor() {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("Lang4SelfUITestingDisableSpaceMonitor"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        waitForUIToSettle(0.2)

        app.typeKey(.space, modifierFlags: [])
        let results = element("dictionary.results")
        XCTAssertTrue(results.waitForExistence(timeout: 3))
        assertFocused(results)

        simulateHeldSpaceWithRepeats()
        XCTAssertTrue(results.waitForExistence(timeout: 3))
        assertFocused(results)
        XCTAssertEqual(app.textFields["dictionary.search"].value as? String, "Der Hund")
    }

    func testVoicePermissionSetupDoesNotStartRecording() {
        app.terminate()
        app.launchArguments.append("--ui-testing-speech-permission-setup")
        app.launch()
        XCTAssertTrue(app.textFields["dictionary.search"].waitForExistence(timeout: 8))

        let setupButton = app.buttons["dictionary.voice-permission"]
        XCTAssertTrue(setupButton.waitForExistence(timeout: 3))
        XCTAssertTrue(element("dictionary.voice-status").exists)
        assertFocused(setupButton)
        app.typeKey(.return, modifierFlags: [])

        let voiceButton = app.buttons["dictionary.voice-search"]
        XCTAssertTrue(voiceButton.waitForExistence(timeout: 3))
        XCTAssertEqual(voiceButton.label, "Start recording")
        XCTAssertEqual(app.textFields["dictionary.search"].value as? String, "")
    }

    func testSpaceOpensDictionaryVoiceSearchFromAnotherPage() {
        openRoute("5", route: "settings")

        app.typeKey(.space, modifierFlags: [])

        XCTAssertTrue(app.buttons["dictionary.voice-search"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.textFields["dictionary.search"].value as? String, "Der Hund")
        XCTAssertTrue(app.buttons["dictionary.add-selected"].waitForExistence(timeout: 3))
        let results = element("dictionary.results")
        XCTAssertTrue(results.waitForExistence(timeout: 3))
        assertFocused(results)
    }

    func testReviewRevealAndEveryRatingShortcut() {
        for rating in ["1", "2", "3", "4"] {
            relaunchFixture()
            openRoute("2", route: "review")
            XCTAssertTrue(app.buttons["review.reveal"].waitForExistence(timeout: 3))

            app.typeKey(.space, modifierFlags: [])
            XCTAssertTrue(app.buttons["review.rating.\(rating)"].waitForExistence(timeout: 3))
            app.typeKey(rating, modifierFlags: [])
            XCTAssertTrue(app.buttons["review.reveal"].waitForExistence(timeout: 3))
        }
    }

    func testReviewPromptShowsPartOfSpeechBeforeReveal() {
        openRoute("2", route: "review")

        let partOfSpeech = element("review.part-of-speech")
        XCTAssertTrue(partOfSpeech.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Part of speech: Noun"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["review.reveal"].exists)
    }

    func testReviewCyclesTranslationsAndLanguagesWithArrowKeys() {
        func text(of element: XCUIElement) -> String {
            if let value = element.value as? String, !value.isEmpty { return value }
            return element.label
        }

        app.typeKey("f", modifierFlags: .command)
        app.typeText("Mädchen")
        let addButton = app.buttons["dictionary.add-selected"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 3))
        addButton.click()
        XCTAssertTrue(app.buttons["banner.dismiss"].waitForExistence(timeout: 3))

        openRoute("2", route: "review")
        for translation in ["house", "to learn"] {
            XCTAssertTrue(waitUntil {
                text(of: self.element("review.translation.current")) == translation
            })
            app.typeKey(.space, modifierFlags: [])
            XCTAssertTrue(app.buttons["review.rating.4"].waitForExistence(timeout: 3))
            app.typeKey("4", modifierFlags: [])
            XCTAssertTrue(app.buttons["review.reveal"].waitForExistence(timeout: 3))
        }

        let currentTranslation = element("review.translation.current")
        let currentLanguage = element("review.language.current")
        XCTAssertTrue(waitUntil { text(of: currentTranslation) == "chick" })
        XCTAssertTrue(waitUntil { text(of: currentLanguage) == "ENGLISH" })
        let previousTranslation = element("review.translation.previous")
        XCTAssertTrue(previousTranslation.waitForExistence(timeout: 3))
        XCTAssertEqual(text(of: previousTranslation), "girl")
        let nextTranslation = element("review.translation.next")
        XCTAssertTrue(nextTranslation.waitForExistence(timeout: 3))
        XCTAssertEqual(text(of: nextTranslation), "chit")
        XCTAssertTrue(element("review.translation.language-next").waitForExistence(timeout: 3))

        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(waitUntil {
            text(of: currentTranslation) == "chit"
                && text(of: self.element("review.translation.previous")) == "chick"
                && text(of: self.element("review.translation.next")) == "colleen"
        })

        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(waitUntil {
            text(of: currentLanguage) == "RUSSIAN" && text(of: currentTranslation) == "девочка"
        })
        XCTAssertEqual(text(of: element("review.translation.language-previous")), "English: chit")
        XCTAssertEqual(text(of: element("review.translation.language-next")), "English: chit")

        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(waitUntil { text(of: currentTranslation) == "девушка" })
        app.typeKey(.upArrow, modifierFlags: [])
        XCTAssertTrue(waitUntil {
            text(of: currentLanguage) == "ENGLISH" && text(of: currentTranslation) == "chit"
        })
        app.typeKey(.leftArrow, modifierFlags: [])
        XCTAssertTrue(waitUntil { text(of: currentTranslation) == "chick" })
    }

    func testReviewListScopeCompletionAndRestart() {
        openRoute("2", route: "review")

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

        let listPicker = element("library.list-picker")
        let newList = element("library.new-list")
        let listActions = element("library.list-actions")
        XCTAssertTrue(newList.exists)
        XCTAssertTrue(listActions.exists)
        XCTAssertEqual(newList.frame.height, listPicker.frame.height, accuracy: 1)

        app.typeKey("f", modifierFlags: .command)
        let librarySearch = app.textFields["library.search"]
        assertFocused(librarySearch, timeout: 5)
        app.typeText("Haus")
        XCTAssertEqual(librarySearch.value as? String, "Haus")
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
        let notesField = app.textFields["card-editor.notes"]
        XCTAssertTrue(notesField.waitForExistence(timeout: 3))
        assertFocused(notesField)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(notesField.waitForNonExistence(timeout: 3))

        app.typeKey("n", modifierFlags: .command)
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

    func testCardEditorOnlyEditsNotesAndSupportsListMembershipActions() {
        openLibrary()

        let editNotes = app.buttons["library.edit-card"]
        XCTAssertTrue(editNotes.waitForExistence(timeout: 3))
        editNotes.click()
        let notes = app.textFields["card-editor.notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 3))
        assertFocused(notes)
        XCTAssertFalse(app.textFields["card-editor.german"].exists)
        XCTAssertFalse(app.textFields["card-editor.translations"].exists)
        XCTAssertFalse(app.textFields["card-editor.tags"].exists)
        XCTAssertFalse(element("card-editor.kind").exists)
        XCTAssertFalse(element("card-editor.gender").exists)
        app.typeText("Edited entirely from the keyboard")

        app.buttons["card-editor.save"].click()
        XCTAssertTrue(notes.waitForNonExistence(timeout: 3))
        XCTAssertTrue(element("library.card-notes").waitForExistence(timeout: 3))
        XCTAssertEqual(elementText(element("library.card-notes")), "Edited entirely from the keyboard")
        assertFocused(element("library.cards"))
        waitForUIToSettle()

        app.staticTexts["lernen"].click()
        XCTAssertTrue(
            waitUntil { self.app.buttons["library.edit-card"].label == "Edit notes for lernen" },
            "Selecting lernen did not update the detail"
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
        openRoute("4", route: "sentences")
        XCTAssertTrue(element("sentences.list").waitForExistence(timeout: 3))
        assertFocused(element("sentences.list"))
        XCTAssertGreaterThanOrEqual(app.checkBoxes.count, 2)

        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(app.buttons["sentence.token.0"].waitForExistence(timeout: 3))
        assertFocused(app.buttons["sentence.token.0"])
        app.typeKey(.escape, modifierFlags: [])
        assertFocused(app.buttons["sentence.token.0"])
        app.typeKey(.rightArrow, modifierFlags: [])
        assertFocused(app.buttons["sentence.token.1"])
        app.typeKey(.leftArrow, modifierFlags: [])
        assertFocused(app.buttons["sentence.token.0"])
        app.typeKey(.leftArrow, modifierFlags: [])
        assertFocused(element("sentences.list"))

        app.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Das Kind liest ein Buch."].waitForNonExistence(timeout: 3))

        let firstCheckbox = app.checkBoxes.firstMatch
        let oldValue = String(describing: firstCheckbox.value)
        app.typeKey("x", modifierFlags: [])
        XCTAssertNotEqual(String(describing: firstCheckbox.value), oldValue)
        app.typeKey("x", modifierFlags: [])
        XCTAssertEqual(String(describing: firstCheckbox.value), oldValue)

        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.buttons["banner.dismiss"].waitForExistence(timeout: 3))
    }

    func testSentenceGenerationListCountAndGenerateControls() {
        openRoute("4", route: "sentences")

        element("sentences.list-picker").click()
        app.menuItems["Travel"].click()

        let level = element("sentences.level")
        XCTAssertTrue(level.exists)
        level.click()
        app.menuItems["C1"].click()
        XCTAssertTrue(element("sentences.minimum-words").exists)
        XCTAssertTrue(element("sentences.maximum-words").exists)

        let minimumWords = app.textFields["sentences.minimum-words-input"]
        let maximumWords = app.textFields["sentences.maximum-words-input"]
        minimumWords.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeText("6")
        maximumWords.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeText("12")

        let style = app.textFields["sentences.style"]
        XCTAssertTrue(style.exists)
        style.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeText("friendly dialogue")

        let count = app.textFields["sentences.count-input"]
        XCTAssertTrue(count.exists)
        count.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeText("6")

        element("sentences.generate").click()
        XCTAssertTrue(app.staticTexts["Das Haus hat ein rotes Dach."].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Der Zug kommt pünktlich an."].waitForExistence(timeout: 3), "Stepper did not increase generation count")
        XCTAssertEqual(app.checkBoxes.count, 6)
        assertFocused(element("sentences.list"))
    }

    func testDetachedSeparablePrefixShowsTheWholeVerbTranslation() {
        openRoute("4", route: "sentences")

        let sentence = app.staticTexts["Das Blatt fällt ab."]
        XCTAssertTrue(sentence.waitForExistence(timeout: 3))
        sentence.click()

        let initialTokenCenters = (0...3).map { index in
            let frame = app.buttons["sentence.token.\(index)"].frame
            return CGPoint(x: frame.midX, y: frame.midY)
        }
        app.buttons["sentence.token.3"].click()

        XCTAssertTrue(app.buttons["sentence.token.2"].isSelected)
        XCTAssertTrue(app.buttons["sentence.token.3"].isSelected)
        XCTAssertTrue(app.staticTexts["to fall off"].waitForExistence(timeout: 3))
        for index in 0...3 {
            let frame = app.buttons["sentence.token.\(index)"].frame
            XCTAssertEqual(
                frame.midX,
                initialTokenCenters[index].x,
                accuracy: 0.5,
                "Selecting another word moved a token horizontally"
            )
            XCTAssertEqual(
                frame.midY,
                initialTokenCenters[index].y,
                accuracy: 0.5,
                "Selecting another word moved a token vertically"
            )
        }

        app.buttons["sentence.token.0"].click()
        XCTAssertTrue(waitUntil {
            self.app.buttons["sentence.token.0"].isSelected
                && self.app.buttons["sentence.token.1"].isSelected
        })
        XCTAssertTrue(app.staticTexts["leaf"].waitForExistence(timeout: 3))
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

        for shortcut in ["global.routes", "global.settings", "global.find", "global.help", "dictionary.add", "dictionary.voice-search", "lists.new", "review.rate", "lists.delete", "macos.quit", "macos.undo"] {
            XCTAssertTrue(element("shortcut.\(shortcut)").exists, "Settings is missing \(shortcut)")
        }
        for oldTextShortcut in ["⌘1 … ⌘5", "⌘F", "⌘Return", "1 … 4", "Delete"] {
            XCTAssertFalse(app.staticTexts[oldTextShortcut].exists, "Shortcut is still rendered as text: \(oldTextShortcut)")
        }

        app.buttons["settings.import-dictionary"].click()
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.buttons["settings.import-dictionary"].waitForExistence(timeout: 3))

        app.buttons["settings.import-explanations"].click()
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.buttons["settings.import-explanations"].waitForExistence(timeout: 3))

        let model = element("settings.model")
        let settingsScroll = app.scrollViews["settings.scroll"]
        XCTAssertTrue(settingsScroll.exists)
        scrollToHittable(model, in: settingsScroll)
        model.click()
        app.menuItems["UI Test Model — 1B · 1 GB"].click()

        element("settings.context-window").click()
        app.menuItems["262,144 tokens"].click()
        element("settings.max-output").click()
        app.menuItems["16,384 tokens"].click()

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
        for (key, route) in [("1", "dictionary"), ("2", "review"), ("3", "library"), ("4", "sentences"), ("5", "settings")] {
            openRoute(key, route: route)
            // Other macOS audit types currently flag system menus and standard SwiftUI layout controls.
            try app.performAccessibilityAudit(for: .elementDetection)
        }
    }

    func testCaptureReadmeScreenshots() {
        app.typeKey("f", modifierFlags: .command)
        app.typeText("Haus")
        XCTAssertTrue(app.staticTexts["Haus"].waitForExistence(timeout: 3))
        attachWindowScreenshot(named: "dictionary")

        openLibrary()
        attachWindowScreenshot(named: "my-words")

        openRoute("4", route: "sentences")
        attachWindowScreenshot(named: "sentences")
    }

    private func openLibrary() {
        openRoute("3", route: "library")
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

    private func elementText(_ element: XCUIElement) -> String {
        if let value = element.value as? String, !value.isEmpty { return value }
        return element.label
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

    private func simulateHeldSpaceWithRepeats() {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("Lang4SelfUITestingSimulateHeldSpace"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    private func attachWindowScreenshot(named name: String) {
        waitForUIToSettle()
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func scrollToHittable(_ element: XCUIElement, in scrollView: XCUIElement) {
        for _ in 0..<4 where !element.isHittable {
            scrollView.swipeUp()
            waitForUIToSettle()
        }
        XCTAssertTrue(element.isHittable, "Could not scroll \(element) into view")
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
        try? writeDictionaryFixtures()
        app.launch()
        XCTAssertTrue(app.textFields["dictionary.search"].waitForExistence(timeout: 8))
    }

    private var englishDictionaryURL: URL {
        testDirectory.appendingPathComponent("fixture-en.txt")
    }

    private var russianDictionaryURL: URL {
        testDirectory.appendingPathComponent("fixture-ru.txt")
    }

    private func writeDictionaryFixtures() throws {
        try """
            # DE-EN vocabulary database
            Mädchen {n}\tchick
            Mädchen {n}\tchit
            Mädchen {n}\tcolleen
            Mädchen {n}\tgal
            Mädchen {n}\tgirl
            Blatt {n}\tleaf
            ab|fallen\tto fall off\tverb\t
            ich\tI; me\tpron
            """.write(to: englishDictionaryURL, atomically: true, encoding: .utf8)
        try """
            # DE-RU vocabulary database
            Mädchen {n}\tдевочка
            Mädchen {n}\tдевушка
            """.write(to: russianDictionaryURL, atomically: true, encoding: .utf8)
    }
}
