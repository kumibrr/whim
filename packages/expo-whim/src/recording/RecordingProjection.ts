export type CaptureSource = 'iphone' | 'apple_watch';

export type RecordingProjection = {
  schemaVersion: 1;
  sessionID: string;
  noteID: string;
  source: CaptureSource;
  createdAt: string;
  maximumDurationSeconds: number;
  warningLeadSeconds: number;
};
