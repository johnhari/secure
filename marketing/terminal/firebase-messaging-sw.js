importScripts("https://www.gstatic.com/firebasejs/9.22.1/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/9.22.1/firebase-messaging-compat.js");

// These values must match firebase_options.dart exactly
firebase.initializeApp({
  apiKey: 'AIzaSyB1_n0v8ug6tRgAOJCGtZL81QaURyaM7GE',
  appId: '1:863653253432:web:b1c73526b6f7d40adef1cd',
  messagingSenderId: '863653253432',
  projectId: 'mst7-3fb55',
  authDomain: 'mst7-3fb55.firebaseapp.com',
  databaseURL: 'https://mst7-3fb55-default-rtdb.firebaseio.com',
  storageBucket: 'mst7-3fb55.firebasestorage.app',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  console.log("[firebase-messaging-sw.js] Received background message ", payload);
  const notificationTitle = payload.notification.title;
  const notificationOptions = {
    body: payload.notification.body,
    icon: "/icons/Icon-192.png"
  };

  self.registration.showNotification(notificationTitle, notificationOptions);
});
