# Resume Desk

iPhone app for editing resumes and documents like Google Docs: paged Letter sheets, styles, lists,
Save to Files (writes back to the file you opened), Share PDF, print. PDFs are real text, not
screenshots, so applicant tracking systems can read them.

- `ios/ResumeDesk/web/editor.html` — the editor (generated from the private soeasy repo's
  `editor.template.html` via `python3 make_editor.py --app <path>`; no resume content is baked in).
- `ios/ResumeDesk/EditorController.swift` — WKWebView host + native bridge (`desk` message handler):
  persist, save, open, share, print. Documents are stored in Application Support/state.json.
- `ios/ResumeDesk/web/lib/` — jsPDF 2.5.1, pdf.js 3.11.174, mammoth 1.6.0, so it works offline.

Install: https://assiamahs.github.io/resumedesk/install.html (ad hoc, registered devices).
CI builds unsigned, cloud-signs a `release-testing` IPA with the ASC key, and publishes it to Pages.
