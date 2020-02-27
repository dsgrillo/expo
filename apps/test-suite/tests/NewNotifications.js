'use strict';

import { Platform } from '@unimodules/core';
import Constants from 'expo-constants';
import * as FileSystem from 'expo-file-system';
import * as Notifications from 'expo-notifications';
import { Alert, AppState } from 'react-native';

import * as TestUtils from '../TestUtils';
import { isInteractive } from '../utils/Environment';
import { waitFor } from './helpers';

export const name = 'expo-notifications';

export async function test(t) {
  const shouldSkipTestsRequiringPermissions = await TestUtils.shouldSkipTestsRequiringPermissionsAsync();
  const describeWithPermissions = shouldSkipTestsRequiringPermissions ? t.xdescribe : t.describe;

  t.describe('expo-notifications', () => {
    t.describe('getDevicePushTokenAsync', () => {
      let subscription = null;
      let tokenFromEvent = null;
      let tokenFromMethodCall = null;

      t.beforeAll(() => {
        subscription = Notifications.addPushTokenListener(newEvent => {
          tokenFromEvent = newEvent;
        });
      });

      t.afterAll(() => {
        if (subscription) {
          subscription.remove();
          subscription = null;
        }
      });

      if (Platform.OS === 'android' || Platform.OS === 'ios') {
        t.it('resolves with a string', async () => {
          const devicePushToken = await Notifications.getDevicePushTokenAsync();
          t.expect(typeof devicePushToken.data).toBe('string');
          tokenFromMethodCall = devicePushToken;
        });
      }

      if (Platform.OS === 'web') {
        t.it('resolves with an object', async () => {
          const devicePushToken = await Notifications.getDevicePushTokenAsync();
          t.expect(typeof devicePushToken.data).toBe('object');
          tokenFromMethodCall = devicePushToken;
        });
      }

      t.it('emits an event with token (or not, if getDevicePushTokenAsync failed)', async () => {
        // It would be better to do `if (!tokenFromMethodCall) { pending(); } else { ... }`
        // but `t.pending()` still doesn't work.
        await waitFor(500);
        t.expect(tokenFromEvent).toEqual(tokenFromMethodCall);
      });

      // Not running this test on web since Expo push notification doesn't yet support web.
      const itWithExpoPushToken = ['ios', 'android'].includes(Platform.OS) ? t.it : t.xit;
      itWithExpoPushToken('fetches Expo push token', async () => {
        let experienceId = undefined;
        if (!Constants.manifest) {
          // Absence of manifest means we're running out of managed workflow
          // in bare-expo. @exponent/bare-expo "experience" has been configured
          // to use Apple Push Notification key that will work in bare-expo.
          experienceId = '@exponent/bare-expo';
        }
        const expoPushToken = await Notifications.getExpoPushTokenAsync({
          experienceId,
        });
        t.expect(expoPushToken.type).toBe('expo');
        t.expect(typeof expoPushToken.data).toBe('string');
      });
    });

    // Not running those tests on web since Expo push notification doesn't yet support web.
    const describeWithExpoPushToken = ['ios', 'android'].includes(Platform.OS)
      ? t.describe
      : t.xdescribe;

    describeWithExpoPushToken('when a push notification is sent', () => {
      let notificationToHandle;
      let handleSuccessEvent;
      let handleErrorEvent;

      let receivedEvent = null;
      let receivedSubscription = null;

      let expoPushToken;

      let handleFuncOverride;

      t.beforeAll(async () => {
        let experienceId = undefined;
        if (!Constants.manifest) {
          // Absence of manifest means we're running out of managed workflow
          // in bare-expo. @exponent/bare-expo "experience" has been configured
          // to use Apple Push Notification key that will work in bare-expo.
          experienceId = '@exponent/bare-expo';
        }
        const pushToken = await Notifications.getExpoPushTokenAsync({
          experienceId,
        });
        expoPushToken = pushToken.data;

        Notifications.setNotificationHandler({
          handleNotification: async notification => {
            notificationToHandle = notification;
            if (handleFuncOverride) {
              return await handleFuncOverride(notification);
            } else {
              return {
                shouldPlaySound: false,
                shouldSetBadge: false,
                shouldShowAlert: true,
              };
            }
          },
          handleSuccess: event => {
            handleSuccessEvent = event;
          },
          handleError: (...event) => {
            handleErrorEvent = event;
          },
        });

        receivedSubscription = Notifications.addNotificationReceivedListener(event => {
          receivedEvent = event;
        });
      });

      t.beforeEach(async () => {
        receivedEvent = null;
        handleErrorEvent = null;
        handleSuccessEvent = null;
        notificationToHandle = null;
        await sendTestPushNotification(expoPushToken);
      });

      t.afterAll(() => {
        if (receivedSubscription) {
          receivedSubscription.remove();
          receivedSubscription = null;
        }
        Notifications.setNotificationHandler(null);
      });

      t.it('calls the `handleNotification` callback of the notification handler', async () => {
        let iterations = 0;
        while (iterations < 5) {
          iterations += 1;
          if (notificationToHandle) {
            break;
          }
          await waitFor(1000);
        }
        t.expect(notificationToHandle).not.toBeNull();
      });

      t.it('emits a “notification received” event', async () => {
        let iterations = 0;
        while (iterations < 5) {
          iterations += 1;
          if (receivedEvent) {
            break;
          }
          await waitFor(1000);
        }
        t.expect(receivedEvent).not.toBeNull();
      });

      t.describe('if handler responds in time', async () => {
        t.it(
          'calls `handleSuccess` callback of the notification handler',
          async () => {
            let iterations = 0;
            while (iterations < 5) {
              iterations += 1;
              if (handleSuccessEvent) {
                break;
              }
              await waitFor(1000);
            }
            t.expect(handleSuccessEvent).not.toBeNull();
            t.expect(handleErrorEvent).toBeNull();
          },
          10000
        );
      });

      t.describe('if handler fails to respond in time', async () => {
        t.beforeAll(() => {
          handleFuncOverride = async () => {
            await waitFor(3000);
            return {
              shouldPlaySound: false,
              shouldSetBadge: false,
              shouldShowAlert: true,
            };
          };
        });

        t.afterAll(() => {
          handleFuncOverride = null;
        });

        t.it(
          'calls `handleError` callback of the notification handler',
          async () => {
            let iterations = 0;
            while (iterations < 5) {
              iterations += 1;
              if (handleErrorEvent) {
                break;
              }
              await waitFor(1000);
            }
            t.expect(handleErrorEvent).not.toBeNull();
            t.expect(typeof handleErrorEvent[0]).toBe('string');
            t.expect(handleSuccessEvent).toBeNull();
          },
          10000
        );
      });
    });

    t.describe('getPermissionsAsync', () => {
      t.it('resolves with an object', async () => {
        const permissions = await Notifications.getPermissionsAsync();
        t.expect(permissions).toBeDefined();
        t.expect(typeof permissions).toBe('object');
      });
    });

    describeWithPermissions('requestPermissionsAsync', () => {
      t.it('resolves without any arguments', async () => {
        const permissions = await Notifications.requestPermissionsAsync();
        t.expect(permissions).toBeDefined();
        t.expect(typeof permissions).toBe('object');
      });

      t.it('resolves with specific permissions requested', async () => {
        const permissions = await Notifications.requestPermissionsAsync({
          providesAppNotificationSettings: true,
          allowsAlert: true,
          allowsBadge: true,
          allowsSound: true,
        });
        t.expect(permissions).toBeDefined();
        t.expect(typeof permissions).toBe('object');
      });
    });

    t.describe('presentNotificationAsync', () => {
      t.it('presents a simple notification', async () => {
        await Notifications.presentNotificationAsync({
          title: 'Sample title',
          subtitle: 'What an event!',
          message: 'An interesting event has just happened',
          badge: 1,
        });
      });

      t.it('presents a notification with attachments', async () => {
        const fileUri = FileSystem.documentDirectory + 'expo-notifications-test-image.jpg';
        await FileSystem.downloadAsync('http://placekitten.com/200/300', fileUri);
        await Notifications.presentNotificationAsync({
          title: 'Look at that kitten! ➡️',
          message: 'What a cutie!',
          ios: {
            attachments: [{ uri: fileUri }],
          },
          android: {
            thumbnailUri: fileUri,
          },
        });
      });
    });

    t.describe('getAllScheduledNotificationsAsync', () => {
      const identifier = 'test-scheduled-notification';
      const notification = { title: 'Scheduled notification' };

      t.afterEach(async () => {
        await Notifications.cancelScheduledNotificationAsync(identifier);
      });

      t.it('resolves with an Array', async () => {
        const notifications = await Notifications.getAllScheduledNotificationsAsync();
        t.expect(notifications).toEqual(t.jasmine.arrayContaining([]));
      });

      t.it('contains a scheduled notification', async () => {
        const trigger = {
          seconds: 10,
        };
        await Notifications.scheduleNotificationAsync(identifier, notification, trigger);
        const notifications = await Notifications.getAllScheduledNotificationsAsync();
        t.expect(notifications).toContain(
          t.jasmine.objectContaining({
            identifier,
            notification: t.jasmine.objectContaining(notification),
            trigger: t.jasmine.objectContaining({
              repeats: false,
              value: trigger.seconds,
              type: 'interval',
            }),
          })
        );
      });

      t.it('does not contain a canceled notification', async () => {
        const trigger = {
          seconds: 10,
        };
        await Notifications.scheduleNotificationAsync(identifier, notification, trigger);
        await Notifications.cancelScheduledNotificationAsync(identifier);
        const notifications = await Notifications.getAllScheduledNotificationsAsync();
        t.expect(notifications).not.toContain(t.jasmine.objectContaining({ identifier }));
      });
    });

    t.describe('scheduleNotificationAsync', () => {
      const identifier = 'test-scheduled-notification';
      const notification = { title: 'Scheduled notification' };

      t.afterEach(async () => {
        await Notifications.cancelScheduledNotificationAsync(identifier);
      });

      t.it(
        'triggers a notification which emits an event',
        async () => {
          const notificationReceivedSpy = t.jasmine.createSpy('notificationReceived');
          const subscription = Notifications.addNotificationReceivedListener(
            notificationReceivedSpy
          );
          await Notifications.scheduleNotificationAsync(identifier, notification, { seconds: 5 });
          await waitFor(6000);
          t.expect(notificationReceivedSpy).toHaveBeenCalled();
          subscription.remove();
        },
        10000
      );

      t.it(
        'triggers a notification which triggers the handler',
        async () => {
          let notificationFromEvent = undefined;
          Notifications.setNotificationHandler({
            handleNotification: async event => {
              notificationFromEvent = event;
              return {
                shouldShowAlert: true,
              };
            },
          });
          await Notifications.scheduleNotificationAsync(identifier, notification, { seconds: 5 });
          await waitFor(6000);
          t.expect(notificationFromEvent).toBeDefined();
          Notifications.setNotificationHandler(null);
        },
        10000
      );

      // iOS rejects with "time interval must be at least 60 if repeating"
      // and having a test running for more than 60 seconds may be too
      // time-consuming to maintain
      if (Platform.OS !== 'ios') {
        t.it(
          'triggers a repeating notification which emits events',
          async () => {
            let timesSpyHasBeenCalled = 0;
            const subscription = Notifications.addNotificationReceivedListener(() => {
              timesSpyHasBeenCalled += 1;
            });
            await Notifications.scheduleNotificationAsync(identifier, notification, {
              seconds: 5,
              repeats: true,
            });
            await waitFor(12000);
            t.expect(timesSpyHasBeenCalled).toBeGreaterThan(1);
            subscription.remove();
          },
          16000
        );
      }

      if (Platform.OS === 'ios') {
        t.it(
          'schedules a notification with calendar trigger',
          async () => {
            const notificationReceivedSpy = t.jasmine.createSpy('notificationReceived');
            const subscription = Notifications.addNotificationReceivedListener(
              notificationReceivedSpy
            );
            await Notifications.scheduleNotificationAsync(identifier, notification, {
              ios: {
                second: (new Date().getSeconds() + 5) % 60,
              },
            });
            await waitFor(6000);
            t.expect(notificationReceivedSpy).toHaveBeenCalled();
            subscription.remove();
          },
          16000
        );
      }
    });

    const onlyInteractiveDescribe = isInteractive ? t.describe : t.xdescribe;
    onlyInteractiveDescribe('when the app is in background', () => {
      let subscription = null;
      let handleNotificationSpy = null;
      let handleSuccessSpy = null;
      let handleErrorSpy = null;
      let notificationReceivedSpy = null;

      t.beforeEach(async () => {
        handleNotificationSpy = t.jasmine.createSpy('handleNotificationSpy');
        handleSuccessSpy = t.jasmine.createSpy('handleSuccessSpy');
        handleErrorSpy = t.jasmine.createSpy('handleErrorSpy').and.callFake((...args) => {
          console.log(args);
        });
        notificationReceivedSpy = t.jasmine.createSpy('notificationReceivedSpy');
        Notifications.setNotificationHandler({
          handleNotification: handleNotificationSpy,
          handleSuccess: handleSuccessSpy,
          handleError: handleErrorSpy,
        });
        subscription = Notifications.addNotificationReceivedListener(notificationReceivedSpy);
      });

      t.afterEach(() => {
        if (subscription) {
          subscription.remove();
          subscription = null;
        }
        Notifications.setNotificationHandler(null);
        handleNotificationSpy = null;
        handleSuccessSpy = null;
        handleErrorSpy = null;
        notificationReceivedSpy = null;
      });

      t.it(
        'shows the notification',
        // without async-await the code is executed immediately after opening the screen
        async () =>
          await new Promise((resolve, reject) => {
            const secondsToTimeout = 5;
            let notificationSent = false;
            Alert.alert(`Please move the app to the background and wait for 5 seconds`);
            let userInteractionTimeout = null;
            async function handleStateChange(state) {
              const identifier = 'test-interactive-notification';
              if (state === 'background' && !notificationSent) {
                if (userInteractionTimeout) {
                  clearInterval(userInteractionTimeout);
                  userInteractionTimeout = null;
                }
                await Notifications.scheduleNotificationAsync(
                  identifier,
                  {
                    title: 'Hello from the application!',
                    message:
                      'You can now return to the app and let the test know the notification has been shown.',
                  },
                  { seconds: 1 }
                );
                notificationSent = true;
              } else if (state === 'active' && notificationSent) {
                const notificationWasShown = await askUserYesOrNo('Was the notification shown?');
                t.expect(notificationWasShown).toBeTruthy();
                t.expect(handleNotificationSpy).not.toHaveBeenCalled();
                t.expect(handleSuccessSpy).not.toHaveBeenCalled();
                t.expect(handleErrorSpy).not.toHaveBeenCalledWith(identifier);
                t.expect(notificationReceivedSpy).not.toHaveBeenCalled();
                AppState.removeEventListener('change', handleStateChange);
                resolve();
              }
            }
            userInteractionTimeout = setTimeout(() => {
              AppState.removeEventListener('change', handleStateChange);
              Alert.alert(
                'Scheduled notification test was skipped',
                `The test required user interaction which hasn't occurred in time (${secondsToTimeout} seconds). It has been marked as passing. Better luck next time!`
              );
              resolve();
            }, secondsToTimeout * 1000);
            AppState.addEventListener('change', handleStateChange);
          }),
        30000
      );
    });
  });
}

// In this test app we contact the Expo push service directly. You *never*
// should do this in a real app. You should always store the push tokens on your
// own server or use the local notification API if you want to notify this user.
const PUSH_ENDPOINT = 'https://expo.io/--/api/v2/push/send';

async function sendTestPushNotification(expoPushToken, notificationOverrides) {
  // POST the token to the Expo push server
  const response = await fetch(PUSH_ENDPOINT, {
    method: 'POST',
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/json',
    },
    body: JSON.stringify([
      {
        to: expoPushToken,
        title: 'Hello from Expo server!',
        ...notificationOverrides,
      },
    ]),
  });

  const result = await response.json();
  if (result.errors) {
    for (const error of result.errors) {
      console.warn(`API error sending push notification:`, error);
    }
    throw new Error('API error has occurred.');
  }

  const receipts = result.data;
  if (receipts) {
    const receipt = receipts[0];
    if (receipt.status === 'error') {
      if (receipt.details) {
        console.warn(
          `Expo push service reported an error sending a notification: ${receipt.details.error}`
        );
      }
      if (receipt.__debug) {
        console.warn(receipt.__debug);
      }
      throw new Error(`API error has occurred: ${receipt.details.error}`);
    }
  }
}

function askUserYesOrNo(title, message = '') {
  return new Promise((resolve, reject) => {
    try {
      Alert.alert(
        title,
        message,
        [
          {
            text: 'No',
            onPress: () => resolve(false),
          },
          {
            text: 'Yes',
            onPress: () => resolve(true),
          },
        ],
        { onDismiss: () => resolve(false) }
      );
    } catch (e) {
      reject(e);
    }
  });
}
