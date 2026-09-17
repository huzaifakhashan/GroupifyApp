/**
 * Import function triggers from their respective submodules:
 *
 * const {onCall} = require("firebase-functions/v2/https");
 * const {onDocumentWritten} = require("firebase-functions/v2/firestore");
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

const {setGlobalOptions} = require("firebase-functions");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {getMessaging} = require("firebase-admin/messaging");
const {getFirestore} = require("firebase-admin/firestore");
const {initializeApp} = require("firebase-admin/app");

initializeApp();
const db = getFirestore();

// For cost control, you can set the maximum number of containers that can be
// running at the same time. This helps mitigate the impact of unexpected
// traffic spikes by instead downgrading performance. This limit is a
// per-function limit. You can override the limit for each function using the
// `maxInstances` option in the function's options, e.g.
// `onRequest({ maxInstances: 5 }, (req, res) => { ... })`.
// NOTE: setGlobalOptions does not apply to functions using the v1 API. V1
// functions should each use functions.runWith({ maxInstances: 10 }) instead.
// In the v1 API, each function can only serve one request per container, so
// this will be the maximum concurrent request count.
setGlobalOptions({ maxInstances: 10 });

exports.notifyOnMessage = onDocumentCreated(
		"messages/{messageId}",
		async (event) => {
			const message = event.data?.data();
			if (!message) return;

			const sender = message.sender || "مستخدم";
			const type = message.type || "text";
			const body = type === "image" ? "📷 صورة" :
				type === "video" ? "🎥 فيديو" :
					type === "audio" ? "🎤 رسالة صوتية" :
						(message.text || "رسالة جديدة");

			let userSnapshot;
			if (message.receiver) {
				userSnapshot = await db.collection("users")
						.where("email", "==", message.receiver).limit(1).get();
			} else if (message.chatType === "public") {
				userSnapshot = await db.collection("users").get();
			} else {
				return;
			}

			const tokens = [];
			userSnapshot.forEach((doc) => {
				const data = doc.data();
				if (data.email !== sender && data.fcmToken) {
					tokens.push(data.fcmToken);
				}
			});
			if (tokens.length === 0) return;

			await getMessaging().sendEachForMulticast({
				tokens: [...new Set(tokens)],
				notification: {
					title: `رسالة جديدة من ${message.name || sender}`,
					body,
				},
				data: {
					messageId: event.params.messageId,
					sender,
					type,
				},
			});
		},
);
