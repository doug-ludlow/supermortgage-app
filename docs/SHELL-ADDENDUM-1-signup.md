# Shell addendum 1 — the sign-up step

This adds one step to Milestone 1. Everything in `SHELL-SPEC.md` still holds; where this addendum and the spec disagree, this addendum wins. The updated HTML in `docs/prototype/` already contains the step — read it first (`signupOpen`, `signupClose`, `auth`, `authEmail` in the `act` map; the `know` screen in `onboarding`; the `.ag-auth*`, `.ag-lets` and `.ag-x` styles).

## What changes

On the **Here's how I work:** page, **Get started** no longer goes straight to *Setting up your agent*. It switches the page into its sign-up state — same page, same system, our branding throughout (nothing from any other app's sign-in screen):

1. The page re-renders (`enter` fade) with a back button top-left (our `icon-button` in `chrome`, back chevron) that returns to the bullets.
2. The mark, then the heading **Setup your home assistant** in the onboarding h1 style. Nothing under it.
3. At the bottom, where Get started was, three stacked doors (`.ag-door`: 52pt, 16pt radius, `surface` fill, `cardLine` border, body size weight 600, icon + label centered, 10pt apart), then the existing terms line under them:
   - **Continue with Apple** — inverted: `text` fill, `paper` label, Apple logo (the `APPLE` SVG from the HTML as an asset). In dark mode this becomes a white button with a black logo, which is Apple's white style.
   - **Continue with Google** — the four-color G (the `GOOGLE` SVG).
   - **Log in or sign up** — an envelope icon (the `mail` path from the icon set).

No dark panel, no typewriter headline, no pulsing dot, no × — those belonged to the screenshot, not to us.

## What the buttons do in the shell

There is no backend yet, so all three doors are fixtures, exactly as in the HTML:

- **Apple** and **Google**: all three buttons disable; the tapped one shows a small spinner and reads "Continuing with Apple…" / "Continuing with Google…"; after 1.1s the step closes and the app goes to *Setting up your agent* as before. Record `account = .init(provider: .apple | .google)` on the model and add the log entry "Signed up with Apple" / "Signed up with Google".
- **Log in or sign up**: the standard sheet titled **Log in or sign up** with one field labeled **Email** (placeholder `you@example.com`, e-mail keyboard, autocomplete e-mail), the fine print "We’ll send a six-digit code. No password.", and a primary **Continue** (empty field → toast "Enter your email"). Continue replaces it with the **Check your email** sheet: "Enter the six-digit code we sent to **{email}**. It expires in 10 minutes.", a **Code** field (numeric keyboard, one-time-code autofill, six digits, placeholder ••••••), primary **Continue** (fewer than six digits → toast "Six digits") and a link **Send a new code** (toast "Code sent again"). Continue closes the sheet, records `account = .init(provider: .email, email:)`, logs "Signed up with e-mail · {email}", and after 0.6s goes to *Setting up your agent*.

Draw the Apple button yourself for now (the inverted style above, the Apple logo from `APPLE` in the HTML as an SVG asset, the label), routed to the fixture path above; do **not** call `AuthenticationServices` in this milestone — the real Sign in with Apple exchange needs the API to verify the identity token, so it lands with Milestone 2, when this button becomes `SignInWithAppleButton(.continue)` and the Google button gets its flow. Add nothing else: no password field, no code-entry screen, no "forgot" link.

## Settings

Settings gains an **Account** section above Connections: one row reading "Signed in with Apple" / "Signed in with Google" / "Signed in with e-mail · {email}" (or "Not signed in"), the small line "Your agent, home and history belong to this account", and a secondary **Sign out** button. Sign out resets the whole model (same as Delete) and returns to Welcome with the toast "Signed out".

## Model, tests, walk

- `AppModel`: `signup: Bool` (false), `account: Account?` (nil). `signupOpen()`, `signupClose()`, `auth(provider)`, `authEmail(_:)` mirror the HTML. Settings → Your data → Delete resets both.
- Unit tests: Get started sets `signup` true and stage stays `.know`; back sets it false; each door records the account, writes the log line and ends at `.chat` (clock injected, delays zero).
- The walk: after "Get started", wait for `button.Continue with Apple`, tap it, then continue exactly as before from "Chat intro → Hazel". Keep a screenshot of the sign-up state.
- Accessibility identifiers: `signup.back`, `button.Continue with Apple`, `button.Continue with Google`, `button.Log in or sign up`, `signup.email`, `button.Continue`.
- Copy is verbatim from the HTML, including the typographic apostrophe in "We’ll".
