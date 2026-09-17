import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:groupify_app/Screens/CallScreen.dart';

class IncomingCallScreen extends StatelessWidget {

final String callId;
final String callerName;
final String callerEmail;
final bool isVideoCall;


const IncomingCallScreen({
super.key,
required this.callId,
required this.callerName,
required this.callerEmail,
this.isVideoCall = false,
});

Future<void> _respond(BuildContext context, String status) async {
  await FirebaseFirestore.instance
      .collection("calls")
      .doc(callId)
      .update({"status": status});

  if (!context.mounted) return;

  if (status == "accepted") {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => Callscreen(
          callId: callId,
          userName: callerName,
          userEmail: callerEmail,
          isVideoCall: isVideoCall,
        ),
      ),
    );
  } else {
    Navigator.pop(context);
  }
}


@override
Widget build(BuildContext context){

return Scaffold(

backgroundColor: Colors.black,

body: Center(

child: Column(

mainAxisAlignment: MainAxisAlignment.center,

children: [


CircleAvatar(
radius:60,
child: Icon(
Icons.person,
size:70,
),
),


SizedBox(height:20),


Text(
callerName,
style: TextStyle(
color:Colors.white,
fontSize:25
),
),


Text(
isVideoCall ? "مكالمة فيديو..." : "مكالمة صوتية...",
style: TextStyle(
color:Colors.white70
),
),


SizedBox(height:40),


Row(

mainAxisAlignment:
MainAxisAlignment.center,

children:[


CircleAvatar(

backgroundColor:Colors.green,

child:IconButton(

icon:Icon(Icons.call),

onPressed:() => _respond(context, "accepted"),

),

),


SizedBox(width:40),


CircleAvatar(

backgroundColor:Colors.red,

child:IconButton(

icon:Icon(Icons.call_end),

onPressed:() => _respond(context, "declined"),

),

),


],)



],

),


),


);


}


}
