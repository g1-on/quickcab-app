import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    if (kIsWeb) return;
    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/launcher_icon');
    const DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
    );
  }

  Future<void> requestPermissions() async {
    if (kIsWeb) return;
    await Permission.notification.request();
    final locationStatus = await Permission.locationWhenInUse.request();
    // Request iOS permissions
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    if (locationStatus.isGranted) {
      await showNotification(
        title: "Location Enabled",
        body: "Your location is now active for QuickCab.",
      );
    }
  }

  Future<void> showNotification({required String title, required String body}) async {
    if (kIsWeb) {
      debugPrint("Web Notification: $title - $body");
      return;
    }
    const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'quickcab_channel_id',
      'QuickCab Notifications',
      channelDescription: 'Notifications for ride updates and messages',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );
    const DarwinNotificationDetails iOSPlatformChannelSpecifics = DarwinNotificationDetails(
      presentSound: true,
      presentAlert: true,
      presentBadge: true,
    );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iOSPlatformChannelSpecifics,
    );
    
    await flutterLocalNotificationsPlugin.show(
      id: DateTime.now().millisecond.remainder(100000),
      title: title,
      body: body,
      notificationDetails: platformChannelSpecifics,
    );
  }
}

final notificationService = NotificationService();
