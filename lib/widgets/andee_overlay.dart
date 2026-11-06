import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

/// Small draggable Andee shortcut shown above other apps after the customer
/// explicitly grants Android's "Display over other apps" permission.
class AndeeFloatingBubble extends StatelessWidget {
  const AndeeFloatingBubble({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Center(
        child: GestureDetector(
          onTap: () async {
            await FlutterOverlayWindow.shareData('open_andee');
            await FlutterOverlayWindow.closeOverlay();
          },
          child: Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: const Color(0xFF6F2438),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, 4)),
              ],
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.auto_awesome, color: Colors.white, size: 25),
                SizedBox(height: 1),
                Text('Andee', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
