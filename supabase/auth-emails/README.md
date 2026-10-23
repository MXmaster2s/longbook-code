# Sign-in emails

`sign-up.html` is the email Supabase Auth sends to an address that has no longbook account yet;
`sign-in.html` goes to one that has. Each carries an 8-digit code that works once and lasts an
hour. Both are **generated** by `scripts/auth-emails.mts` from `scripts/auth-emails/`; edit those,
never these files. CI runs `npm run auth-emails:check`.

| Command | What it does |
|---|---|
| `npm run auth-emails` | writes the two files |
| `npm run auth-emails -- --preview` | writes them with a sample code to a temporary folder, to open in a browser; sends nothing |
| `npm run auth-emails -- --verify` | reads the live project back and compares (needs a Supabase token) |
| `npm run auth-emails -- --deploy` | sets the live subjects and templates, after saving the old ones to a file |
| `npm run auth-emails -- --restore <file>` | puts back what `--deploy` saved |

`{{ .Token }}` and `{{ .ConfirmationURL }}` are Supabase's own placeholders. Nothing else in double
braces may appear in a template, and the generator refuses to run if it does. The deploy also
refuses unless the project's code lifetime (`mailer_otp_exp`) is 3600 seconds, because the emails
say "one hour".
