import React, {
  DeviceEventEmitter,
  NativeModules,
  Platform,
} from 'react-native';
import { EventEmitter } from 'events';

import Call from './Call'
import Message from './Message'
import Account from './Account'

/**
 * SIP headers object, where each key is a header name and value is a header value.
 * Example:
 * {
 *   "X-Custom-Header": "Test Header Value",
 *   "X-Custom-ID": "Awesome Header"
 * }
 *
 * @typedef {Object} PjSipHdrList
 */

/**
 * An additional information to be sent with outgoing SIP message.
 * It can (optionally) be specified for example
 * with #Endpoint.makeCall(), #Endpoint.answerCall(), #Endpoint.hangupCall(),
 * #Endpoint.holdCall() and many more.
 *
 * @typedef {Object} PjSipMsgData
 * @property {String} target_uri - Indicates whether the Courage component is present.
 * @property {PjSipHdrList} hdr_list - Additional message headers as linked list.
 * @property {String} content_type - MIME type of optional message body.
 * @property {String} msg_body - MIME type of optional message body.
 */

/**
 * An additional information to be sent with outgoing SIP message.
 * It can (optionally) be specified for example
 * with #Endpoint.makeCall(), #Endpoint.answerCall(), #Endpoint.hangupCall(),
 * #Endpoint.holdCall() and many more.
 *
 * @typedef {Object} PjSipCallSetttings
 * @property {number} flag - Bitmask of #pjsua_call_flag constants.
 * @property {number} req_keyframe_method - This flag controls what methods to request keyframe are allowed on the call.
 * @property {number} aud_cnt - Number of simultaneous active audio streams for this call. Setting this to zero will disable audio in this call.
 * @property {number} vid_cnt - Number of simultaneous active video streams for this call. Setting this to zero will disable video in this call.
 */



export default class Endpoint extends EventEmitter {

    constructor() {
        super();

        // Subscribe to Accounts events
        DeviceEventEmitter.addListener('pjSipRegistrationChanged', this._onRegistrationChanged.bind(this));

        // Subscribe to Calls events
        DeviceEventEmitter.addListener('pjSipCallReceived', this._onCallReceived.bind(this));
        DeviceEventEmitter.addListener('pjSipCallChanged', this._onCallChanged.bind(this));
        DeviceEventEmitter.addListener('pjSipCallTerminated', this._onCallTerminated.bind(this));
        DeviceEventEmitter.addListener('pjSipCallScreenLocked', this._onCallScreenLocked.bind(this));
        DeviceEventEmitter.addListener('pjSipMessageReceived', this._onMessageReceived.bind(this));
        DeviceEventEmitter.addListener('pjSipConnectivityChanged', this._onConnectivityChanged.bind(this));
        DeviceEventEmitter.addListener('pjSipLogReceived', this._onLogReceived.bind(this));
        DeviceEventEmitter.addListener('pjSipLaunchStatusUpdated', this._onLaunchStatusUpdate.bind(this));
    }

    /**
     * Returns a Promise that will be resolved once PjSip module is initialized.
     * Do not call any function while library is not initialized.
     *
     * @returns {Promise}
     */
    start(configuration) {
        return new Promise(function(resolve, reject) {
            NativeModules.PjSipModule.start(configuration, (successful, data) => {
                if (successful) {
                    let accounts = [];
                    let calls = [];

                    if (data.hasOwnProperty('accounts')) {
                        for (let d of data['accounts']) {
                            accounts.push(new Account(d));
                        }
                    }

                    if (data.hasOwnProperty('calls')) {
                        for (let d of data['calls']) {
                            calls.push(new Call(d));
                        }
                    }

                    let extra = {};

                    for (let key in data) {
                        if (data.hasOwnProperty(key) && key != "accounts" && key != "calls") {
                            extra[key] = data[key];
                        }
                    }

                    resolve({
                        accounts,
                        calls,
                        ...extra
                    });
                } else {
                    reject(data);
                }
            });
        });
    }

    stop() {
        return new Promise(function (resolve, reject) {
            NativeModules.PjSipModule.stop((successful) => {
                resolve(successful);
            });
        })
    }

    isStarted() {
        return new Promise(function (resolve) {
            NativeModules.PjSipModule.isStarted((result, params) => {
                if (result && params) {
                    resolve(params.is_started);
                } else {
                    resolve(false);
                }
            })
        })
    }

    reconnect() {
        return new Promise(function (resolve) {
            NativeModules.PjSipModule.reconnect((result) => {
                resolve(result);
            })
        })
    }

    updateStunServers(accountId, stunServerList) {
        return new Promise(function(resolve, reject) {
            NativeModules.PjSipModule.updateStunServers(accountId, stunServerList, (successful, data) => {
                if (successful) {
                    resolve(data);
                } else {
                    reject(data);
                }
            })
        })
    }

    /**
     * @param configuration
     * @returns {Promise}
     */
    changeNetworkConfiguration(configuration) {
        return new Promise(function(resolve, reject) {
            NativeModules.PjSipModule.changeNetworkConfiguration(configuration, (successful, data) => {
                if (successful) {
                    resolve(data);
                } else {
                    reject(data);
                }
            });
        });
    }

    /**
     * @param configuration
     * @returns {Promise}
     */
    changeServiceConfiguration(configuration) {
        return new Promise(function(resolve, reject) {
            NativeModules.PjSipModule.changeServiceConfiguration(configuration, (successful, data) => {
                if (successful) {
                    resolve(data);
                } else {
                    reject(data);
                }
            });
        });
    }

    setAccountCreds(creds) {
        // return new Promise(function(resolve, reject) {
            NativeModules.PjSipModule.setAccountCreds(creds, (successful, data) => {
                // if (successful) {
                //     resolve(new Account(data));
                // } else {
                //     reject(data);
                // }
            });
        // });
    }

    registerExistingAccountIfNeeded() {
      NativeModules.PjSipModule.registerExistingAccountIfNeeded(() => {});
    }

    getCurrentAccount() {
      return new Promise((resolve, reject) => {
          NativeModules.PjSipModule.getCurrentAccount((successful, data) => {
            if (successful && data) {
              resolve(new Account(data));
            } else {
              reject(data);
            }
          });
      })
    }

    /**
     * Make an outgoing call to the specified URI.
     * Available call settings:
     * - audioCount - Number of simultaneous active audio streams for this call. Setting this to zero will disable audio in this call.
     * - videoCount - Number of simultaneous active video streams for this call. Setting this to zero will disable video in this call.
     * -
     *
     * @param account {Account}
     * @param destination {String} Destination SIP URI.
     * @param callSettings {PjSipCallSetttings} Outgoing call settings.
     * @param msgSettings {PjSipMsgData} Outgoing call additional information to be sent with outgoing SIP message.
     */
    makeCall(account, destination, callSettings, msgData) {
        destination = this._normalize(account, destination);

        return new Promise(function(resolve, reject) {
            NativeModules.PjSipModule.makeCallToDestination(destination, callSettings, msgData, (successful, data) => {
                if (successful) {
                    resolve(new Call(data));
                } else {
                    reject(data);
                }
            });
        });
    }

    /**
     * Send response to incoming INVITE request.
     *
     * @param call {Call} Call instance
     * @returns {Promise}
     */
    answerCall(call) {
        return new Promise((resolve, reject) => {
            NativeModules.PjSipModule.answerCall(call.getId(), (successful, data) => {
                if (successful) {
                    resolve(data);
                } else {
                    reject(data);
                }
            });
        });
    }

    /**
     * Hangup call by using method that is appropriate according to the call state.
     *
     * @param call {Call} Call instance
     * @returns {Promise}
     */
    hangupCall(call) {
        // TODO: Add possibility to pass code and reason for hangup.
        return new Promise((resolve, reject) => {
            NativeModules.PjSipModule.hangupCall(call.getId(), (successful, data) => {
                if (successful) {
                    resolve(data);
                } else {
                    reject(data);
                }
            });
        });
    }

    /**
     * Hangup call by using Decline (603) method.
     *
     * @param call {Call} Call instance
     * @returns {Promise}
     */
    declineCall(call) {
        return this.declineCallWithReason(call, 0);
    }

    declineCallWithReason(call, reason) {
        const key = Platform.OS === 'android' ? 'call_id' : 'callId';
        return new Promise((resolve, reject) => {
            NativeModules.PjSipModule.declineCall({ [key]: call.getId(), reason }, (successful, data) => {
                if (successful) {
                    resolve(data);
                } else {
                    reject(data);
                }
            });
        });
    }

    /**
     * Put the specified call on hold. This will send re-INVITE with the appropriate SDP to inform remote that the call is being put on hold.
     *
     * @param call {Call} Call instance
     * @returns {Promise}
     */
    holdCall(call) {
        return new Promise((resolve, reject) => {
            NativeModules.PjSipModule.holdCall(call.getId(), (successful, data) => {
                if (successful) {
                    resolve(data);
                } else {
                    reject(data);
                }
            });
        });
    }

    /**
     * Release the specified call from hold. This will send re-INVITE with the appropriate SDP to inform remote that the call is resumed.
     *
     * @param call {Call} Call instance
     * @returns {Promise}
     */
    unholdCall(call) {
        return new Promise((resolve, reject) => {
            NativeModules.PjSipModule.unholdCall(call.getId(), (successful, data) => {
                if (successful) {
                    resolve(data);
                } else {
                    reject(data);
                }
            });
        });
    }

    /**
     * @param call {Call} Call instance
     * @returns {Promise}
     */
    muteCall(call) {
        return new Promise((resolve, reject) => {
            NativeModules.PjSipModule.muteCall(call.getId(), (successful, data) => {
                if (successful) {
                    resolve(data);
                } else {
                    reject(data);
                }
            });
        });
    }

    /**
     * @param call {Call} Call instance
     * @returns {Promise}
     */
    unMuteCall(call) {
        return new Promise((resolve, reject) => {
            NativeModules.PjSipModule.unMuteCall(call.getId(), (successful, data) => {
                if (successful) {
                    resolve(data);
                } else {
                    reject(data);
                }
            });
        });
    }

    /**
     * @param call {Call} Call instance
     * @returns {Promise}
     */
    useSpeaker(call) {
        return new Promise((resolve, reject) => {
            NativeModules.PjSipModule.useSpeaker(call.getId(), (successful, data) => {
                if (successful) {
                    resolve(data);
                } else {
                    reject(data);
                }
            });
        });
    }

    /**
     * @param call {Call} Call instance
     * @returns {Promise}
     */
    useEarpiece(call) {
        return new Promise((resolve, reject) => {
            NativeModules.PjSipModule.useEarpiece(call.getId(), (successful, data) => {
                if (successful) {
                    resolve(data);
                } else {
                    reject(data);
                }
            });
        });
    }

    /**
     * Initiate call transfer to the specified address.
     * This function will send REFER request to instruct remote call party to initiate a new INVITE session to the specified destination/target.
     *
     * @param account {Account} Account associated with call.
     * @param call {Call} The call to be transferred.
     * @param destination URI of new target to be contacted. The URI may be in name address or addr-spec format.
     * @returns {Promise}
     */
    xferCall(account, call, destination) {
        destination = this._normalize(account, destination);

        return new Promise((resolve, reject) => {
            NativeModules.PjSipModule.xferCall(call.getId(), destination, (successful, data) => {
                if (successful) {
                    resolve(data);
                } else {
                    reject(data);
                }
            });
        });
    }

    /**
     * Initiate attended call transfer.
     * This function will send REFER request to instruct remote call party to initiate new INVITE session to the URL of destCall.
     * The party at destCall then should "replace" the call with us with the new call from the REFER recipient.
     *
     * @param call {Call} The call to be transferred.
     * @param destCall {Call} The call to be transferred.
     * @returns {Promise}
     */
    xferReplacesCall(call, destCall) {
        return new Promise((resolve, reject) => {
            NativeModules.PjSipModule.xferReplacesCall(call.getId(), destCall.getId(), (successful, data) => {
                if (successful) {
                    resolve(data);
                } else {
                    reject(data);
                }
            });
        });
    }

    /**
     * Redirect (forward) specified call to destination.
     * This function will send response to INVITE to instruct remote call party to redirect incoming call to the specified destination/target.
     *
     * @param account {Account} Account associated with call.
     * @param call {Call} The call to be transferred.
     * @param destination URI of new target to be contacted. The URI may be in name address or addr-spec format.
     * @returns {Promise}
     */
    redirectCall(account, call, destination) {
        destination = this._normalize(account, destination);

        return new Promise((resolve, reject) => {
            NativeModules.PjSipModule.redirectCall(call.getId(), destination, (successful, data) => {
                if (successful) {
                    resolve(data);
                } else {
                    reject(data);
                }
            });
        });
    }

    /**
     * Send DTMF digits to remote using RFC 2833 payload formats.
     *
     * @param call {Call} Call instance
     * @param digits {String} DTMF string digits to be sent as described on RFC 2833 section 3.10.
     * @returns {Promise}
     */
    dtmfCall(call, digits) {
        return new Promise((resolve, reject) => {
            NativeModules.PjSipModule.dtmfCall(call.getId(), digits, (successful, data) => {
                if (successful) {
                    resolve(data);
                } else {
                    reject(data);
                }
            });
        });
    }

    activateAudioSession() {
        return new Promise((resolve, reject) => {
            NativeModules.PjSipModule.activateAudioSession((successful, data) => {
                if (successful) {
                    resolve(data);
                } else {
                    reject(data);
                }
            });
        });
    }

    deactivateAudioSession() {
        return new Promise((resolve, reject) => {
            NativeModules.PjSipModule.deactivateAudioSession((successful, data) => {
                if (successful) {
                    resolve(data);
                } else {
                    reject(data);
                }
            });
        });
    }

    changeOrientation(orientation) {
      const orientations = [
        'PJMEDIA_ORIENT_UNKNOWN',
        'PJMEDIA_ORIENT_ROTATE_90DEG',
        'PJMEDIA_ORIENT_ROTATE_270DEG',
        'PJMEDIA_ORIENT_ROTATE_180DEG',
        'PJMEDIA_ORIENT_NATURAL'
      ]

      if (orientations.indexOf(orientation) === -1) {
        throw new Error(`Invalid ${JSON.stringify(orientation)} device orientation, but expected ${orientations.join(", ")} values`)
      }

      NativeModules.PjSipModule.changeOrientation(orientation)
    }

    changeCodecSettings(codecSettings) {
        return new Promise(function(resolve, reject) {
        NativeModules.PjSipModule.changeCodecSettings(codecSettings, (successful, data) => {
                if (successful) {
                    resolve(data);
                } else {
                    reject(data);
                }
            });
        });
    }

    getCodecs() {
        return new Promise((resolve) => {
            NativeModules.PjSipModule.getCodecs(codecs => {
                resolve(codecs);
            });
        })
    }

    getLogsFilePathUrl() {
        return new Promise((resolve, reject) => {
            NativeModules.PjSipModule.getLogsFilePathUrl((success, data)=> {
                const url = success && data && data.url;
                if (url) {
                    resolve(url)
                } else {
                    reject();
                }
            })
        })
    }

    /**
     * @fires Endpoint#connectivity_changed
     * @private
     * @param data {Object}
     */
    _onConnectivityChanged(data) {
        /**
         * Fires when registration status has changed.
         *
         * @event Endpoint#connectivity_changed
         * @property {Account} account
         */
        this.emit("connectivity_changed", new Account(data));
    }

    /**
     * @fires Endpoint#registration_changed
     * @private
     * @param data {Object}
     */
    _onRegistrationChanged(data) {
        /**
         * Fires when registration status has changed.
         *
         * @event Endpoint#registration_changed
         * @property {Account} account
         */
        this.emit("registration_changed", { account: new Account(data.account), regInfo: data.regInfo });
    }

    /**
     * @fires Endpoint#call_received
     * @private
     * @param data {Object}
     */
    _onCallReceived(data) {
        /**
         * TODO
         *
         * @event Endpoint#call_received
         * @property {Call} call
         */
        this.emit("call_received", new Call(data));
    }

    /**
     * @fires Endpoint#call_changed
     * @private
     * @param data {Object}
     */
    _onCallChanged(data) {
        /**
         * TODO
         *
         * @event Endpoint#call_changed
         * @property {Call} call
         */
        this.emit("call_changed", new Call(data));
    }

    /**
     * @fires Endpoint#call_terminated
     * @private
     * @param data {Object}
     */
    _onCallTerminated(data) {
        /**
         * TODO
         *
         * @event Endpoint#call_terminated
         * @property {Call} call
         */
        this.emit("call_terminated", new Call(data));
    }

    /**
     * @fires Endpoint#call_screen_locked
     * @private
     * @param lock bool
     */
    _onCallScreenLocked(lock) {
        /**
         * TODO
         *
         * @event Endpoint#call_screen_locked
         * @property bool lock
         */
        this.emit("call_screen_locked", lock);
    }

    /**
     * @fires Endpoint#message_received
     * @private
     * @param data {Object}
     */
    _onMessageReceived(data) {
        /**
         * TODO
         *
         * @event Endpoint#message_received
         * @property {Message} message
         */
        this.emit("message_received", new Message(data));
    }

    _onLogReceived(data) {
      this.emit("log_received", data);
    }

    _onLaunchStatusUpdate(data) {
      this.emit('launch_status_update', data);
    }

    /**
     * @fires Endpoint#connectivity_changed
     * @private
     * @param available bool
     */
    _onConnectivityChanged(available) {
        /**
         * @event Endpoint#connectivity_changed
         * @property bool available True if connectivity matches current Network settings, otherwise false.
         */
        this.emit("connectivity_changed", available);
    }

    /**
     * Normalize Destination URI
     *
     * @param account
     * @param destination {string}
     * @returns {string}
     * @private
     */
    _normalize(account, destination) {
        if (!destination.startsWith("sip:")) {
            let realm = account.getRegServer();

            if (!realm) {
                realm = account.getDomain();
                let s = realm.indexOf(":");

            }

            destination = "sip:" + destination + "@" + realm;
        }

        return destination;
    }
    // setUaConfig(UaConfig value)
    // setMaxCalls
    // setUserAgent
    // setNatTypeInSdp

    // setLogConfig(LogConfig value)
    // setLevel
}

export function pjLogMessage(message) {
    return new Promise((resolve) => {
        NativeModules.PjSipModule.logMessage(message, () => {
            resolve()
        });
    })
}
