# Keep BitWatch's own Kotlin classes referenced only via MethodChannel
# reflection-free calls; nothing special required, but keep the service and
# receiver classes fully so the manifest component names resolve at runtime.
-keep class com.bitwatch.app.** { *; }

# Flutter embedding
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
