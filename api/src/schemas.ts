import { z } from 'zod';

// Every request and response shape, once. The ids in the global registry become the named
// component schemas of openapi.yaml, and the iOS types are generated from those (tools/gen-swift.ts).

const isoDate = z.iso.datetime({ offset: true }).describe('ISO 8601 timestamp');

export const Provider = z.enum(['apple', 'google', 'email']);
export const OnboardingStage = z.enum(['know', 'setup', 'chat']);

export const User = z.object({
  id: z.uuid(),
  email: z.string().nullable(),
  emailVerified: z.boolean(),
  displayName: z.string().nullable(),
  providers: z.array(Provider).describe('Every door this account has used'),
  signedInWith: Provider.describe('The door of the current session'),
  createdAt: isoDate,
});

export const Household = z.object({
  id: z.uuid(),
  createdAt: isoDate,
});

export const Agent = z.object({
  name: z.string().nullable(),
  namedAt: isoDate.nullable(),
});

export const Onboarding = z.object({
  stage: OnboardingStage,
  completedAt: isoDate.nullable(),
});

export const Me = z.object({
  user: User,
  household: Household,
  agent: Agent,
  onboarding: Onboarding,
});

export const EmailStartRequest = z.object({
  email: z.string().min(1).max(320),
});

export const EmailVerifyRequest = z.object({
  email: z.string().min(1).max(320),
  code: z.string().min(1).max(16),
});

export const EmailVerifyResponse = z.object({
  customToken: z.string().describe('Exchange with Auth.auth().signIn(withCustomToken:)'),
});

export const AgentPatch = z.object({
  name: z.string().trim().min(1).max(24),
});

export const OnboardingPatch = z.object({
  stage: OnboardingStage,
});

export const Health = z.object({
  ok: z.boolean(),
  version: z.string(),
  db: z.enum(['ok', 'error']),
});

export const Problem = z.object({
  error: z.string().describe('A stable machine-readable code'),
});

export const Empty = z.object({});

export const StubMail = z.object({
  to: z.string(),
  subject: z.string(),
  text: z.string(),
  code: z.string().nullable(),
});

export const meExample = {
  user: {
    id: '7b8f5a6e-4c1d-4e2a-9f3b-1a2b3c4d5e6f',
    email: 'doug@example.com',
    emailVerified: true,
    displayName: null,
    providers: ['apple'],
    signedInWith: 'apple',
    createdAt: '2026-09-18T00:00:00.000Z',
  },
  household: { id: '0c2f6f1e-5d3a-4b7c-8e9f-2b3c4d5e6f70', createdAt: '2026-09-18T00:00:00.000Z' },
  agent: { name: 'Hazel', namedAt: '2026-09-18T00:01:00.000Z' },
  onboarding: { stage: 'chat', completedAt: '2026-09-18T00:01:00.000Z' },
};

export const meFreshExample = {
  ...meExample,
  user: { ...meExample.user, email: 'walk@example.com', providers: ['email'], signedInWith: 'email' },
  agent: { name: null, namedAt: null },
  onboarding: { stage: 'know', completedAt: null },
};

z.globalRegistry.add(Provider, { id: 'Provider' });
z.globalRegistry.add(OnboardingStage, { id: 'OnboardingStage' });
z.globalRegistry.add(User, { id: 'User' });
z.globalRegistry.add(Household, { id: 'Household' });
z.globalRegistry.add(Agent, { id: 'Agent' });
z.globalRegistry.add(Onboarding, { id: 'Onboarding' });
z.globalRegistry.add(Me, { id: 'Me', examples: [meExample, meFreshExample] });
z.globalRegistry.add(EmailStartRequest, { id: 'EmailStartRequest', examples: [{ email: 'you@example.com' }] });
z.globalRegistry.add(EmailVerifyRequest, { id: 'EmailVerifyRequest', examples: [{ email: 'you@example.com', code: '482913' }] });
z.globalRegistry.add(EmailVerifyResponse, { id: 'EmailVerifyResponse', examples: [{ customToken: 'eyJhbGciOiJSUzI1NiJ9.e30.sig' }] });
z.globalRegistry.add(AgentPatch, { id: 'AgentPatch', examples: [{ name: 'Hazel' }] });
z.globalRegistry.add(OnboardingPatch, { id: 'OnboardingPatch', examples: [{ stage: 'chat' }] });
z.globalRegistry.add(Health, { id: 'Health', examples: [{ ok: true, version: 'supermortgage-app-api-00012-abc', db: 'ok' }] });
z.globalRegistry.add(Problem, { id: 'Problem', examples: [{ error: 'code_invalid' }] });
z.globalRegistry.add(Empty, { id: 'Empty' });

export type MeShape = z.infer<typeof Me>;
export type ProviderName = z.infer<typeof Provider>;
export type OnboardingStageName = z.infer<typeof OnboardingStage>;
