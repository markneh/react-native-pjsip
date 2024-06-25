declare module 'react-native-pjsip' {
  import EventEmitter from 'events';

  type Registration = {
    isActive(): boolean;
    getStatusText(): string;
  };

  // eslint-disable-next-line no-shadow
  enum DeclineCallReason {
    Unknown = 0,
    Busy = 1,
  }

  export type Account = {
    getRegistration(): Registration;
    getURI(): string;
    getUsername(): string;
  };

  export type RegInfo = {
    success: boolean;
    code: number;
    reason: string;
  };

  export type RegistrationEvent = {
    account: Account;
    regInfo: RegInfo;
  };

  export enum AndroidCallState {
    PJSIP_INV_STATE_NULL = 0,
    PJSIP_INV_STATE_CALLING = 1,
    PJSIP_INV_STATE_INCOMING = 2,
    PJSIP_INV_STATE_EARLY = 3,
    PJSIP_INV_STATE_CONNECTING = 4,
    PJSIP_INV_STATE_CONFIRMED = 5,
    PJSIP_INV_STATE_DISCONNECTED = 6,
  }

  export type SipCallState =
    | 'PJSIP_INV_STATE_NULL'
    | 'PJSIP_INV_STATE_CALLING'
    | 'PJSIP_INV_STATE_INCOMING'
    | 'PJSIP_INV_STATE_EARLY'
    | 'PJSIP_INV_STATE_CONNECTING'
    | 'PJSIP_INV_STATE_CONFIRMED'
    | 'PJSIP_INV_STATE_DISCONNECTED'
    | AndroidCallState;

  export type SipCall = {
    getId(): number;
    getXCallId(): string;
    getAccountId(): number;
    getCallId(): string;
    getFormattedConnectDuration(): string;
    getLocalContact(): string;
    getLocalUri(): string;
    getRemoteContact(): string;
    getRemoteName(): string;
    getRemoteNumber(): string;
    getRemoteFormattedNumber(): string;
    getRemoteUri(): string;
    getState(): SipCallState;
    getStateText(): string;
    isMuted(): boolean;
    isSpeaker(): boolean;
    getLastStatusCode(): string;
  };

  export type AccountCredentials = {
    name: string;
    password: string;
    username: string;
    domain: string;
  };

  type CreateAccountParams = {
    transport: 'TCP' | 'UDP';
    contactUriParams: string;
    regContactParams?: string;
  } & AccountCredentials;

  type AccountCallback = (account: Account) => void;
  type CallCallback = (call: SipCall) => void;
  type LogCallback = (log: string) => void;

  type CallEventType =
    | 'call_received'
    | 'call_changed'
    | 'call_terminated'
    | 'call_screen_locked';
  type AccountEventType = 'registration_changed' | 'connectivity_changed';
  type LogEventType = 'log_received';

  type AccountListener = (
    event: AccountEventType,
    callback: AccountEventType,
  ) => void;
  type CallListener = (event: CallEventType, callback: CallCallback) => void;

  type CallOperation = (call: SipCall) => Promise<void>;

  type SipInitialState = {
    accounts: Account[];
    calls: SipCall[];
    settings: {
      codecs: unknown;
    };
    regInfo?: RegInfo;
  };

  export class Endpoint extends EventEmitter {
    start(configuration: Object): Promise<SipInitialState>;
    stop(): Promise<boolean>;
    isStarted(): Promise<boolean>;
    reconnect(): Promise<boolean>;
    createAccount(account: CreateAccountParams): Promise<Account>;
    registerAccount(account: Account, register: boolean): Promise<unknown>;
    updateAccountCredentials(
      account: Account,
      credentials: AccountCredentials,
    ): Promise<unknown>;
    deleteAccount(account: Account): Promise<unknown>;
    makeCall(account: Account, destination: string): Promise<SipCall>;
    dtmfCall(call: SipCall, digits: string): Promise<boolean>;
    answerCall: CallOperation;
    declineCall: CallOperation;
    declineCallWithReason: (
      call: SipCall,
      reason: DeclineCallReason,
    ) => Promise<boolean>;
    hangupCall: CallOperation;
    activateAudioSession(): Promise<void>;
    deactivateAudioSession(): Promise<void>;
    muteCall: CallOperation;
    unMuteCall: CallOperation;
    useSpeaker: CallOperation;
    useEarpiece: CallOperation;
    getCodecs(): Promise<unknown>;
    changeCodecSettings(settings: unknown): void;
    getLogsFilePathUrl(): Promise<string>;
    // on(event: CallEventType, callback: CallCallback): void;
    // on(event: LogEventType, callback: LogCallback): void;
    // on(event: AccountEventType, callback: AccountCallback): void;
  }

  export function pjLogMessage(message: {
    type: string;
    content: string;
  }): Promise<boolean>;
}
