const admin = require("firebase-admin");
const serviceAccount = require("./serviceAccountKey.json");

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  databaseURL: "https://mst7-3fb55-default-rtdb.firebaseio.com"
});

admin.auth().listUsers(20)
  .then((listUsersResult) => {
    listUsersResult.users.forEach((userRecord) => {
      console.log('User:', userRecord.email, 'UID:', userRecord.uid, 'EmailVerified:', userRecord.emailVerified);
    });
    process.exit(0);
  })
  .catch((error) => {
    console.error("Error listing users:", error);
    process.exit(1);
  });
