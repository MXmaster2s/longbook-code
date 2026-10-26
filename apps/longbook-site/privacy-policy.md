# Privacy Policy

> What personal data longbook collects, why it is processed, who processes it, how long it is kept, and the rights available to you.

- Page: https://longbook.app/privacy-policy/

This policy describes the processing of personal data by longbook. It should be read together with the [Terms of Service](https://longbook.app/terms). Section 2 is a summary; the sections that follow are the policy itself.

CONTENTS

1. About this policy
2. Summary
3. Data held on your own devices
4. Personal data we collect
5. Purposes and legal bases
6. Uses we do not make of your data
7. Service providers
8. International transfers
9. Retention
10. Security
11. Your rights
12. Children
13. Cookies, analytics and local storage
14. Changes to this policy
15. Controller, grievance contact and how to reach us

## About this policy

This Privacy Policy explains what personal data longbook collects, the purposes for which it is processed, and the rights available to you. It covers the website at longbook.app, the longbook applications for macOS and iOS, and the hosted services.

The controller of personal data is identified in section 15.

Capitalised terms not defined here have the meaning given to them in the [Terms of Service](https://longbook.app/terms).

## Summary

Financial records created in longbook are stored in your Memory File, a file held in your own device storage and your own iCloud Drive, in the folder you chose. By default our servers never receive it and we cannot read it. The exceptions are features you turn on or use yourself: the copy used by the hosted MCP server, a report you share, a statement you import, which is read and not kept, and the Memory File itself when you ask for it to be reorganised, which is read for that one pass and not kept. When you are signed in, your Account also keeps the names, icons and layouts of your tags, never an amount, a date, a note or a record. Each is described in section 4.

When you switch on the hosted MCP server in the application, a copy of your Memory File is stored with your Account at our database provider, Supabase, which encrypts it in transit using TLS and at rest using AES-256. The copy can be read only through your Account or with an access key you create. Switching the hosted MCP server off deletes the copy at once, and a copy the application has not refreshed for ninety (90) days — because the application was removed, for instance — is deleted automatically, as is a copy whose Account has been without a Cloud subscription for thirty (30) days.

We do not use the contents of your financial records for analytics, for advertising or to train models, and we do not sell them or share them with anyone for their own purposes.

What reaches our servers is an email address, licence status and the status of your Cloud subscription, together with two optional copies of data that you switch on yourself, and, when you choose to import one, a bank or card statement that is read and then discarded, and, when you choose to reorganise your Memory File, the file itself, read for that pass and then discarded.

Visits to the website are counted with PostHog, configured to set no cookies and to keep nothing in your browser. The applications send PostHog usage counts and crash reports under a random identifier kept on your device, which is not linked to your Account and is deleted when you switch sharing off, and contain no advertising SDKs. PostHog never receives the contents of your Memory File.

This summary is provided for convenience. The sections that follow govern.

## Data held on your own devices

The Memory File is written to your device and synchronised through your own iCloud account under your agreement with Apple. It is not sent to us, except through the optional features described in section 4 that you turn on or use yourself.

The file format records dates, amounts, names, categories and notes. The applications reject a record carrying a payment card number, CVV, expiry date, PIN or account credential.

## Personal data we collect

**Account data.** Your email address, the date the account was made, whether a licence has been purchased, and the status of your Cloud subscription. This is created when you sign in. If you sign in with Google, your name and the address of your Google profile picture arrive with the sign-in; the application shows the picture by loading it from Google, and we keep no copy of it.

**Account notices.** We email you when your Account is signed in, when you turn the hosted MCP server on or off, and when you share a report. A sign-in notice carries what the sign-in session records: its time, whether it used an emailed code or Google or Apple, a description of the application or browser, and its IP address. A report notice carries the report’s title and when its link expires. What a notice copies about a sign-in is held only until the email is sent or given up, and then removed. The record that a notice was sent is kept for thirty (30) days.

**Sign-in code counts.** When a sign-in code is emailed to you, a cryptographic hash of your email address and the time of sending are kept for one (1) hour, in order to limit how many codes are sent to one address, and to all addresses together, within an hour. The address itself does not form part of this record.

**Hosted memory copy — optional.** When you enable the hosted MCP server in the application, the application uploads a copy of the Memory File as it stands, and replaces it each time you save. Files in your documents folder are never part of it. The copy is readable by an AI you sign in with your Account, or by an AI holding an access key you create in the application; each key is stored only as a hash, with its name, permissions, expiry and last use. An AI cannot change the copy. A change it proposes is stored with the name of the AI that made it until your application applies it to your Memory File, where you keep or undo it; an applied proposal is kept, marked applied, with your Account. Disabling the setting deletes the copy at once, and revoking a key or an AI connection stops that AI at once. The application refreshes the copy while it is in use; a copy it has not refreshed for ninety (90) days — because the application was removed, for instance — is deleted automatically, as is a copy whose Account has been without a Cloud subscription for thirty (30) days.

**Shared reports — optional.** A report you publish is stored, protected by a password longbook generates, and deleted at once when you revoke it or within a day after its link expires. Comments left in a shared report are stored with it.

**Statement reading — on request.** When you import a bank or card statement in the application, the file is sent, a few pages or rows at a time, from your device to our server and from there to Anthropic, whose Claude model first checks that the file is a statement and then reads it and returns the charges it holds, together with the names of the categories, members and accounts already in your Memory File and your home currency. A PDF is rebuilt page by page on your device before it is sent, so that only its pages travel; the pages carry what the bank printed, so any account number on them travels with them; a password you enter to open a locked PDF stays on your device. Our server keeps neither the statement nor the charges. It records only that an import happened: your Account, an identifier for the import, its start and last-call times, whether the file was read or refused as not a statement, the number of model calls and the tokens they consumed. The start times are how the monthly share of reading is counted, which is larger with a Cloud subscription, and the tokens how one import’s budget is. When Anthropic’s service cannot answer, the same piece is sent to OpenAI instead.

**Reorganising — on request.** When you choose **Reorganise my longbook** in the application, your Memory File is sent from your device to our server and from there to Anthropic, whose Claude model reads it against longbook’s written method and returns a list of proposed changes: names, categories and links between records, never an amount or a date. The proposals come back to your device and wait in the application’s Proposals screen as one proposal, which you keep or undo. Our server keeps neither the file nor the proposals. It records only that a run happened: your Account, an identifier for the run, its start and last-call times, whether the run answered or failed, the number of model calls and the tokens they consumed. The start times are how the monthly share of runs is counted, which is larger with a Cloud subscription.

**AI connections.** A record of which assistants you have authorised. These are listed and revocable in the application.

**Tag vocabulary.** When you are signed in, the definitions of the tags you use — their kind, name, icon and field layout — are stored with your Account so that your devices and authorised assistants share one vocabulary. Amounts, dates, notes and records are never part of it.

**Correspondence.** Messages sent to [contact@longbook.app](mailto:contact@longbook.app) and the address they come from.

**Support conversations — on request.** When you ask a question in Support, in the applications or on the website, the question and the earlier messages of that conversation are sent to our server, which passes them to Anthropic to write an answer from our published help articles. With them our server receives your IP address and, if you are signed in to an application, the token that identifies your account, or otherwise a random identifier that the application keeps, or the web page holds, for Support only. Our server does not keep the text of any message. It keeps, for each person and day, a count of the questions asked, under an identifier derived one way from the account, the random identifier or the IP address, so that a daily limit can be applied; and, for each answer, whether it was answered from the help articles, which articles it used, the rating you give it, if any, and, when it was not answered, a short topic of a few words written without names or numbers. No part of your Memory File is sent.

**Writing to the team — on request.** If you ask Support for a person, or choose to tell us about an answer that did not help, Support opens your own email application with a message to our support address, containing the conversation, the version of the application and the type of device, the rating you gave, if any, and, if you attached one, the screenshot. Nothing is sent until you send that email yourself, and it is then handled as described for email you send us. Our server sends no email for Support. A screenshot is never sent to the AI.

**Service counts.** For the hosted MCP server, the number of connections opened, the number of tool calls and the number of changes proposed each day, counted separately for each AI application as its requests name it — Claude or ChatGPT, for instance. For each day, AI application and way of connecting (a signed-in connection or an access key), we also count the connections opened under the name the AI’s software gives itself when it connects, and the calls made to each tool, by the tool’s name. The counts are kept in our database with no Account, access key, IP address or other identifier attached, and never include what a tool was asked or answered. Use of the MCP server that runs on your own computer is not counted.

**Purchase data.** A purchase is made inside the application and handled by Apple through the App Store. We receive confirmation of the purchase, the email address on the Account and Apple’s transaction identifiers; we do not receive payment card details. The application sends Apple an identifier for your Account with each purchase, so that Apple’s records of it can be matched to the Account.

**Cloud subscription.** For the longbook Cloud subscription we hold its status (active, in a grace period, in billing retry, expired or revoked), the date the current period ends, whether it is set to renew, the product purchased, whether it was bought in Apple’s production or sandbox environment, Apple’s original transaction identifier for it, and the time of the latest signed record Apple sent about it. Apple sends our server a signed notification when the subscription starts, renews, changes its renewal setting, fails to renew, enters or leaves a grace period, expires, is refunded or revoked, or is extended, and each notification updates that status. We do not receive your Apple ID or payment details.

**Website usage data.** When you visit longbook.app we record the page viewed and its title, the website that referred you, your browser’s user-agent string (which names the browser, the operating system and the type of device) and your time zone. On each page we also record the links, buttons and questions you click or open, by the words on them and the part of the page they sit in; the section headings you scroll to; and, when you leave the page, how long it was open, how far down you scrolled, and how quickly it loaded and responded. For a download link, we also record which button it was and whether it was for Mac or iPhone. If one of the website’s own scripts fails, we record the error message and the file and line it came from; an error raised by a browser extension or by another website’s script is not recorded. Nothing you type is recorded. Cloudflare determines the country, and where it can the city, from your IP address as the request arrives, and the page sends those two words with the visit; no finer location is kept. This is collected with PostHog in its cookieless mode: no cookie is set for measurement and no identifier is kept in your browser. Visits are told apart by a hash that PostHog derives from your IP address and browser details using a salt that changes every day, so that visits are not linked to a person, across days, or across websites. We have configured PostHog to discard your IP address once it has been used, so it is not stored with the visit. Addresses are recorded without their query strings. When a link to the website carries campaign tags (utm_source, utm_medium, utm_campaign or utm_content), those tags are recorded with the visit, so that we can tell which post or message led to it; a tag holding anything other than a plain label is dropped. Advertising click identifiers and search keywords, including the utm_term tag, are not recorded. A browser that sends a Global Privacy Control or Do Not Track signal is not measured, and you can switch measurement off for your browser in the section on cookies below. The pages that show a shared report carry no measurement. On the consent screen, where you allow an AI to connect to your Account, we record only that the screen opened with a request on it and whether you allowed or refused it, each with the name the AI registered; the email address shown, the address the AI returns to and the request’s identifier are not recorded, and the same signals and switch apply. What the applications send is described under application usage data below.

**Website traffic through Cloudflare.** Every request to longbook.app passes through Cloudflare, which delivers the website and shields it from automated and harmful traffic. Cloudflare receives your IP address and the details your browser sends with each request, and determines from the IP address the country the request comes from. It shows us totals of requests, including by country; we do not keep them. The country and the city it determines are also sent with each measured visit, as described above; nothing else from Cloudflare is joined to that measurement. Cloudflare handles this data as our service provider and under its own privacy policy.

**Application usage data.** The applications send PostHog a short record when one of the following happens: the application is opened, with whether you are signed in, the type of device (iPhone, iPad or Mac) and, on iPhone and iPad, how many longbook widgets are placed; the application leaves the screen or quits, with how long it was in front, rounded to five seconds, and how many screens were opened; a screen is opened, with the name of the screen; a sheet, message or menu is shown over it, or a button, switch or menu item is used, by the fixed name the application gives it and the screen it is on, never the words on it or what you typed; a step of first-run setup is shown, or setup ends, with how long it took; the demo longbook is opened; a statement import ends, with whether it succeeded, how many charges it found, how many files and pieces it held, how many were PDFs and their total size rounded to fifty kilobytes; a file is refused as not a statement; the server has read its share of statements for the month; the hosted MCP server is switched on or off; your Memory File changes, with the number of records changed, who signed them in the file (the application itself, Claude, ChatGPT, Gemini, Cursor, another assistant, or no one) and whether the change came through the hosted MCP server, was found in the file, or was made in the application; a change made to your Memory File outside the application — by an AI, for instance — is kept or undone; a report is shared or revoked; the application handles an error while importing a statement, refreshing the hosted copy, sharing a report, making a purchase, signing in, or opening or saving the Memory File, with where it happened and its general kind (network, file access, file format, App Store, sign-in or unknown), never the error’s text or a file path; for a sign-in, also the way it was attempted (Apple, Google, sending an emailed code or entering it) and the fixed code that Apple, Google or our sign-in service returned with the refusal; or a licence or a Cloud subscription is purchased. Each record carries the version and build of the application, the platform (macOS or iOS) and the version of the operating system. The first time a record is sent, the application makes a random identifier and keeps it in its own settings on that device; each record carries it, so that records from one installation can be told apart from another’s and counted across days. The identifier is not derived from your device, your Apple ID or your Account; it is not stored with your Account, sent to our servers or shared with the website’s measurement; and it differs on each device. Switching off **Share usage and crash data** deletes it, and switching sharing back on makes a new one, so that later records cannot be connected to earlier ones. Deleting the application from iPhone or iPad also deletes it. PostHog keeps no profile of a person from these records. As with website visits, we have configured PostHog to discard your IP address once it has been used. A record never contains the contents of your Memory File — names, amounts, dates, notes, merchants or accounts — nor your email address or your Account identifier. PostHog reads the country and the city from the IP address as a record arrives and keeps those two words; no finer location is inferred. You can switch this off with **Share usage and crash data** on the Help & about screen of the application. Builds made for development in Xcode send nothing; TestFlight and App Store builds send what this section describes, subject to the switch.

**Crash and diagnostic reports.** Apple’s MetricKit framework gives the application a report when it crashes, stops responding, makes heavy use of the processor or of disk writes, or is slow to launch. The application forwards each report to PostHog in the same way as application usage data, under the same identifier. A report contains a stack trace, which lists program addresses and the names of the program and system libraries they belong to; the type and codes of the exception, the signal and the termination reason; and the details MetricKit attaches to the report, including the version and build of the application, the version of the operating system and the model of the device. Before sending, the application removes the text of any exception message, the process number and any description of memory regions, which could otherwise carry a value from the application’s data or a file path. A report never contains the contents of your Memory File, your email address or your Account identifier. The same switch turns these reports off. Separately, if you allow it in your device’s settings, Apple may share crash reports with us through App Store Connect and TestFlight.

**Usage allowance and grants.** Where we grant your Account a different monthly allowance for statement reading, or Cloud without charge, that number or the date the grant ends, and a short note, are kept with your Account.

**Technical logs.** Records of requests made to the hosted services, including IP address and timestamp, generated for security and diagnostics.

## Purposes and legal bases

Personal data is processed for the purposes and on the legal bases set out below. Where the General Data Protection Regulation applies, the basis named is the one relied upon.

- **Licence, Cloud subscription and Account**: Providing the Service you have contracted for — **performance of a contract**
- **Hosted copy, proposed changes, shared reports**: Operating the optional features you enable — **consent**, withdrawable at any time
- **Statement reading**: Reading a statement you import into the charges it holds — **consent**, given each time by choosing to import
- **Reorganising**: Reading your Memory File into proposed names, categories and links — **consent**, given each time by choosing to reorganise
- **Support conversations**: Answering the questions you send through Support — **legitimate interests** (supporting users) and performance of a contract
- **Security and abuse**: Protecting the Service and its users — **legitimate interests**
- **Account notices**: Telling you when your Account is signed in, when the hosted copy is turned on or off, and when you share a report — **legitimate interests** (security) and performance of a contract
- **Sign-in code limits**: Limiting how many sign-in codes are emailed to one address, and in total, within an hour — **legitimate interests** (security)
- **Support**: Answering your messages — **legitimate interests** and performance of a contract
- **Website measurement**: Understanding, in aggregate, which pages and parts of pages are read, what is clicked, how quickly pages load and where they fail, and whether visitors go on to the application — **legitimate interests**
- **Application usage data**: Understanding, in aggregate, which features are used and where the application is hard to use, in order to improve it — **legitimate interests**
- **Crash and diagnostic reports**: Finding and fixing defects in the application — **legitimate interests**
- **Service counts**: Counting, per day and per AI application, how often the hosted MCP server is connected to and called and how many changes are proposed through it, with no identifier — **legitimate interests**
- **Records**: Tax and accounting retention — **legal obligation**

## Uses we do not make of your data

Personal data is not sold, and is not licensed or disclosed to data brokers.

Personal data is not used for advertising and is not shared with advertising networks.

The contents of your financial records — your Memory File, any copy of it held with your Account, and any statement you import, and the file as sent to be reorganised — are not sold, are not used for analytics, for advertising or to train models, and are not shared with anyone for their own purposes. The one number measured about them is how many charges an import added, as described under application usage data.

No profiling and no automated decision-making producing legal or similarly significant effects is carried out.

## Service providers

The following providers process personal data on our behalf, under contract, and only to provide their service to us.

- **Cloudflare**: Network infrastructure, delivery and protection of the website, domain name service, and routing of email sent to us
- **Supabase**: Database, authentication and the hosted services, including the optional hosted memory copy
- **Anthropic**: Checking and reading statements you import, reading your Memory File when you ask for it to be reorganised, and writing the answers given in Support from our help articles, through its Claude API, hosted in the United States; it does not train on the data
- **OpenAI**: Reading a statement when Anthropic’s service cannot answer, through its API, hosted in the United States; the request asks that nothing be stored
- **Netlify**: Hosting and delivery of this website
- **Resend**: Transactional email, including sign-in links
- **PostHog**: Website and application measurement and crash reports, without cookies, hosted in the United States
- **Apple**: iCloud storage, App Store purchases and subscription billing, under your own agreement with Apple

## International transfers

Server-side data is hosted with Supabase in the Asia Pacific (Mumbai) region, `ap-south-1`.

A statement you import, and your Memory File when you ask for it to be reorganised, are processed by Anthropic in the United States to check and read them; Anthropic does not use them to train its models and may keep them for up to thirty (30) days to detect abuse. When Anthropic’s service cannot answer, the piece is processed by OpenAI in the United States instead; our request asks that nothing be stored, OpenAI does not use it to train its models and may keep it for up to thirty (30) days in logs used to detect abuse. Website and application usage data and crash and diagnostic reports are processed by PostHog in the United States. Questions asked in Support are processed by Anthropic in the United States to write an answer; Anthropic does not use them to train its models and may keep them for up to thirty (30) days to detect abuse.

Personal data of users in the European Economic Area and the United Kingdom is therefore transferred outside those areas. Such transfers are made under the European Commission’s standard contractual clauses, together with the UK international data transfer addendum where applicable.

## Retention

Account data is retained while the Account exists and afterwards only for as long as required for tax and accounting records.

The status of the Cloud subscription and Apple’s transaction identifiers are kept with the Account data, for the same period.

The hosted memory copy exists only while the setting is enabled, and is deleted ninety (90) days after your application last refreshed it, or thirty (30) days after the Account’s Cloud subscription lapsed without being resumed. A proposed change from an AI is kept with your Account, marked applied once your application has applied it, and deleted ninety (90) days after it was filed. Access keys are kept, marked revoked, until the Account is deleted.

A shared report and its comments are deleted at once on revocation, and within a day after its link expires.

The text of Support conversations is not kept on our server. In the applications a conversation is kept on your device until you remove it with **Clear support history**; on the website it is kept only in the open page and is gone when the page is closed. The daily counts of questions are deleted after the end of the following day. The records of answers carry no identifier of any person and are kept for as long as they serve to improve the help articles. An email you send us from Support is kept in our support inbox as described for email.

A statement you import, and the charges read from it, are not retained by our server, nor is your Memory File when sent to be reorganised, nor the proposals read from it. The record that an import or a reorganising run happened is retained while the Account exists.

Addresses left on the website before release were deleted on 21 September 2026. The website no longer collects them.

PostHog keeps website and application usage data and crash and diagnostic reports for up to one year under the plan we use, and then deletes them.

Service counts are kept as daily totals that identify no one.

Account notice records are kept for thirty (30) days. The device description and IP address in a sign-in notice are removed when the email is sent or given up.

Sign-in code counts are kept for one (1) hour.

Technical logs are retained for a limited period for security and diagnostics and are then deleted.

## Security

Traffic to the website and to the hosted services is encrypted in transit using TLS.

Our database provider, Supabase, encrypts the data it stores for us, including the hosted memory copy, at rest using AES-256.

Hosted data is scoped to your Account by database access rules. A shared report additionally requires the password issued when it was published.

No system is perfectly secure. The email address on your Account is the key to it and should be protected accordingly.

## Your rights

You may request access to your personal data, its correction or deletion, a portable copy, and restriction of processing, and you may object to processing carried out on the basis of legitimate interests. Where processing rests on consent, that consent may be withdrawn at any time. To keep your visits out of the website’s measurement, use the switch in the section on cookies, or switch on Global Privacy Control or Do Not Track in your browser. To stop the applications sending usage data and crash reports, switch off **Share usage and crash data** on the Help & about screen of the application; this also deletes the identifier described in section 4. Because that identifier is not linked to your Account or to you, we cannot find the records made under it in response to a request.

Portability is largely already in your hands: the Memory File is a structured, readable file that you hold.

Requests are made to [contact@longbook.app](mailto:contact@longbook.app) and are answered within thirty (30) days.

A user in the European Economic Area or the United Kingdom may lodge a complaint with their supervisory authority. A user in India may write to the grievance contact named in section 15.

A California resident has the right to know, delete and correct personal information, and to opt out of its sale or sharing. We do not sell or share personal information as those terms are defined by the California Consumer Privacy Act.

## Children

The Service is not directed to children under the age of sixteen, and personal data of children is not knowingly collected. Where such data has been collected, it is deleted on notice to [contact@longbook.app](mailto:contact@longbook.app).

## Cookies, analytics and local storage

The website sets no cookies of its own, and none for measurement or advertising; the applications set none at all. Cloudflare, which shields the website from automated traffic, may set a short-lived security cookie. Website measurement, described above, uses no cookie and keeps nothing in your browser.

Support on the website is loaded only when you open it, sets no cookies and stores nothing in your browser. In the applications, Support keeps your conversation and its random identifier on your device until you clear them.

You can switch measurement off for this browser here; the choice is kept in your browser’s local storage and nowhere else.

The website stores in your browser’s local storage the light or dark appearance you selected and, if you switch measurement off, that choice.

The applications keep your choice about sharing usage and crash data in their own settings on your device, and the random identifier described under application usage data while sharing is on.

Signing in stores an authentication token on your device so that the session persists.

## Changes to this policy

This policy may be amended. The current version and its effective date are published on this page.

Material changes may be notified by email or in the Application.

## Controller, grievance contact and how to reach us

The controller of personal data described in this policy is **Rohit Kundliwal**, sole proprietor, established in India.

The same person is the grievance contact for the purposes of Indian data protection law. Enquiries and complaints are made to [contact@longbook.app](mailto:contact@longbook.app).

A postal address for the service of legal notices is provided on written request to that address.

This policy took effect on 25 October 2026 and replaces any earlier version. It differs from the version of 24 October 2026 in describing Support in the applications and on the website, which answers from our help articles through Anthropic in place of chat.sh, an email to the team that you send from your own email application, and the rating of answers. The version of 24 October 2026 differed from the earlier version of that day in describing Support on the website, provided by chat.sh. The earlier version of 24 October 2026 differed from the version of 23 October 2026 in describing the records the applications send when a sheet, message or menu is shown or a button, switch or menu item is used. The version of 23 October 2026 differed from that of 19 October 2026 in saying that the country and the city of a website visit are determined by Cloudflare and sent with the visit, where the earlier version said PostHog read them from the IP address. The version of 19 October 2026 differed from that of 15 October 2026 in removing the free trial, which longbook no longer offers: the account data names the date the account was made, and no usage record marks the start of a trial. The version of 15 October 2026 differed from that of 13 October 2026 in describing the reorganising of your Memory File on request, with Anthropic reading it for that one pass and the record of the run kept, and in saying that PostHog keeps the country and the city it reads from an IP address, for website visits and for application records alike, where the earlier version said no location was inferred. The version of 13 October 2026 differed from that of 12 October 2026 in naming Anthropic as the service that checks and reads imported statements, with OpenAI standing in when it cannot answer, in describing the rebuilt PDF pages, the record of a refused file and the monthly share, and in the usage data about an import’s size. The version of 12 October 2026 differed from that of 10 October 2026 in describing the random identifier that the applications keep for usage data and crash reports, the start of a free trial, and the way a failed sign-in was attempted with the code returned. The version of 10 October 2026 differed from that of 8 October 2026 in describing what Cloudflare receives from requests to the website, including the country they come from. The version of 8 October 2026 differed from that of 6 October 2026 in describing more application usage data (the type of device, widgets placed, time in front, errors the application handles by place and kind, and who changed the Memory File), the hosted MCP server’s counts by way of connecting, by the name an AI’s software gives itself and by tool, and the counts taken on the consent screen.

Back to the top
