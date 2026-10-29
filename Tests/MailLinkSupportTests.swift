// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure rules for the option that keeps email links from opening Mail.
enum MailLinkSupportTests {
    static func run(_ suite: TestSuite) {
        func recipients(_ link: String) -> [String] {
            URL(string: link).map(MailLinkSupport.recipients(in:)) ?? []
        }

        suite.expect(recipients("mailto:someone@example.com") == ["someone@example.com"],
                     "a plain link yields its one address")
        suite.expect(recipients("MAILTO:someone@example.com") == ["someone@example.com"],
                     "the scheme is matched without regard to case")
        suite.expect(recipients("mailto:a@example.com,b@example.com?subject=Hi&body=x")
                        == ["a@example.com", "b@example.com"],
                     "several addresses keep their order and the subject and body are left out")
        suite.expect(recipients("mailto:a@example.com?to=b@example.com&cc=c@example.com&bcc=d@example.com")
                        == ["a@example.com", "b@example.com"],
                     "to fields add recipients, copies and blind copies do not")
        suite.expect(recipients("mailto:?to=b@example.com&subject=Hi") == ["b@example.com"],
                     "an empty address part still finds the to field")
        suite.expect(recipients("mailto:first%20last%40example.com") == ["first last@example.com"],
                     "percent escapes are decoded")
        suite.expect(recipients("mailto:a@example.com?to=A@example.com") == ["a@example.com"],
                     "a repeated address is copied once")
        suite.expect(recipients("mailto:?subject=Hi").isEmpty,
                     "a link with no recipient has nothing to copy")
        suite.expect(recipients("https://example.com/mailto:a@example.com").isEmpty
                        && !MailLinkSupport.isMailLink(URL(string: "https://example.com")!),
                     "only mailto links are email links")

        suite.expect(MailLinkSupport.Action.sanitized(nil) == .ignore
                        && MailLinkSupport.Action.sanitized("unknown") == .ignore
                        && MailLinkSupport.Action.sanitized("copyAddress") == .copyAddress,
                     "an unknown or missing choice does nothing")

        let own = "com.vorssaint.utils"
        suite.expect(!MailLinkSupport.canOpenLinks(bundleID: "com.apple.mail", ownBundleID: own)
                        && !MailLinkSupport.canOpenLinks(bundleID: "com.apple.Mail", ownBundleID: own)
                        && !MailLinkSupport.canOpenLinks(bundleID: own, ownBundleID: own)
                        && !MailLinkSupport.canOpenLinks(bundleID: nil, ownBundleID: own),
                     "Mail and this app can't open the links, or the link would come straight back")
        suite.expect(MailLinkSupport.canOpenLinks(bundleID: "com.microsoft.Outlook", ownBundleID: own),
                     "any other mail app can open the links")

        let link = URL(string: "mailto:a@example.com")!
        let other = URL(string: "mailto:b@example.com")!
        suite.expect(MailLinkSupport.isReturnedLink(link, now: 11, lastPassedOn: link, passedOnAt: 10),
                     "the same link coming straight back from the chosen app is dropped")
        suite.expect(!MailLinkSupport.isReturnedLink(link, now: 11, lastPassedOn: other, passedOnAt: 10)
                        && !MailLinkSupport.isReturnedLink(link, now: 10 + MailLinkSupport.returnWindow,
                                                           lastPassedOn: link, passedOnAt: 10)
                        && !MailLinkSupport.isReturnedLink(link, now: 11, lastPassedOn: nil, passedOnAt: nil),
                     "another link, a later click on the same one or a first link is passed on")

        let apps = ["/Applications/Outlook.app": "com.microsoft.Outlook",
                    "/Applications/Vorssaint.app": own]
        func target(_ saved: String?) -> String? {
            MailLinkSupport.restoreTarget(savedPath: saved, ownBundleID: own,
                                          bundleID: { apps[$0] }, exists: { apps[$0] != nil })
        }
        suite.expect(target("/Applications/Outlook.app") == "/Applications/Outlook.app",
                     "turning the option off gives links back to the app that had them")
        suite.expect(target(nil) == nil && target("") == nil
                        && target("/Applications/Removed.app") == nil
                        && target("/Applications/Vorssaint.app") == nil,
                     "with no saved app, a removed one or this app itself, links go back to Mail")
    }
}
