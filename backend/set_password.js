const admin = require("firebase-admin");
const serviceAccount = require("./serviceAccountKey.json");

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  databaseURL: "https://mst7-3fb55-default-rtdb.firebaseio.com"
});

const uid = "halMxVu1u8XXQWSt4sj21iQXIlw2"; // jivaspcet@gmail.com
const newPassword = "14300000Ht@";

admin.auth().updateUser(uid, {
  password: newPassword,
  emailVerified: true
})
  .then((userRecord) => {
    console.log(`✅ Successfully updated user ${userRecord.email} password to ${newPassword}`);
    
    // Also let's set this user's profile role to admin in Firestore
    const db = admin.firestore();
    return db.collection("users").doc(uid).set({
      uid: uid,
      email: "jivaspcet@gmail.com",
      role: "admin",
      isApproved: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });
  })
  .then(() => {
     console.log("✅ Successfully set role to admin in Firestore");
     process.exit(0);
  })
  .catch((error) => {
    console.error("Error updating user:", error);
    process.exit(1);
  });
