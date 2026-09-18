// One HTTP call to the e-mail API (Resend), or a logging stub when MAIL_STUB=1.

export interface Mail {
  to: string;
  subject: string;
  text: string;
}

export interface MailSender {
  send(mail: Mail): Promise<void>;
}

/** The code e-mail, exactly as SIGNUP-FOR-REAL.md §4.2 words it. */
export function codeMail(to: string, code: string): Mail {
  return {
    to,
    subject: 'Your Supermortgage code',
    text: `Your Supermortgage code is ${code}. It expires in 10 minutes. If you didn’t ask for it, ignore this e-mail.`,
  };
}

export class ResendSender implements MailSender {
  constructor(
    private readonly apiKey: string,
    private readonly from: string,
    private readonly fetchImpl: typeof fetch = fetch,
  ) {}

  async send(mail: Mail): Promise<void> {
    const response = await this.fetchImpl('https://api.resend.com/emails', {
      method: 'POST',
      headers: { authorization: `Bearer ${this.apiKey}`, 'content-type': 'application/json' },
      body: JSON.stringify({ from: this.from, to: [mail.to], subject: mail.subject, text: mail.text }),
    });
    if (!response.ok) {
      throw new Error(`mail api responded ${response.status}`);
    }
  }
}

/** Keeps every mail in memory and logs the code. Local development and tests only. */
export class StubSender implements MailSender {
  readonly outbox: Mail[] = [];

  constructor(private readonly log: (fields: Record<string, unknown>, message: string) => void) {}

  async send(mail: Mail): Promise<void> {
    this.outbox.push(mail);
    this.log({ to: mail.to, code: extractCode(mail.text) }, 'mail stub: code e-mail');
  }

  last(to: string): Mail | undefined {
    for (let i = this.outbox.length - 1; i >= 0; i -= 1) {
      const mail = this.outbox[i];
      if (mail && mail.to === to) return mail;
    }
    return undefined;
  }
}

export function extractCode(text: string): string | undefined {
  return /\b(\d{6})\b/.exec(text)?.[1];
}
