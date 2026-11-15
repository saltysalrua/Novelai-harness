# 保留 shared_preferences Pigeon JNI 反射调用的 Kotlin 类与成员，
# 防止 Android Release 构建 R8 裁剪导致 NoSuchMethodError。
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keepclassmembers class io.flutter.plugins.sharedpreferences.** { *; }
