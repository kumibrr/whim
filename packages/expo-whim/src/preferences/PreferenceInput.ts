export type RetentionPolicy =
  | 'immediately'
  | 'one_day'
  | 'seven_days'
  | 'thirty_days'
  | 'ninety_days'
  | 'never';

export type PreferenceInput = {
  retentionPolicy: RetentionPolicy;
  transcriptionEnabled: boolean;
  transcriptionLocaleIdentifier: string | null;
};
