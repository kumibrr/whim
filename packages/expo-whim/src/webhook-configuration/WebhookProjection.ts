export type CustomHeaderInput = { name: string; value: string; isSecret: boolean };

export type WebhookConfigurationInput = {
  endpoint: string;
  bearerToken?: string | null;
  hmacSecret?: string | null;
  customHeaders: CustomHeaderInput[];
};

export type WebhookProjection = {
  schemaVersion: 1;
  revisionID: string;
  destination: { scheme: string; host: string; port: number | null; path: string };
  customHeaderNames: string[];
};

export type ConfigurationUpdateResult = {
  revisionID: string;
  failedCount: number;
  setupRequiredCount: number;
};

export type ConfigurationTestResult = {
  passed: boolean;
  statusCode: number | null;
  idempotencyConfirmed: boolean;
};
