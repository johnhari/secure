var admin = require("firebase-admin");
var serviceAccount = require("./serviceAccountKey.json");

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  databaseURL: "https://mst7-3fb55-default-rtdb.firebaseio.com"
});

const email = "whatsapplivestatus@gmail.com";

admin.auth().getUserByEmail(email)
  .then((userRecord) => {
    console.log("Found user:", userRecord.uid);
    return admin.auth().setCustomUserClaims(userRecord.uid, { admin: true });
  })
  .then(() => {
    console.log(`✅ Admin claim set successfully for ${email}`);
    process.exit(0);
  })
  .catch((error) => {
    console.error("❌ Error:", error.message);
    process.exit(1);
  });
